#!/bin/bash
# shellcheck disable=SC2034,SC2139

export DIR_ENTRY=$(pwd)
export DIR_DEBUG=$DIR_ENTRY/debug
export REBOOT_DOGFILE="/mnt/reboot_dogfile"
export STATUS_FILE=/tmp/process_reg_suit_status

FILE_SKIP_SUMMARY="$DIR_DEBUG/skipped_bugs_summary.txt"

install_packages(){
	rpm -q perf || yum -y install perf
	rpm -q trace-cmd || yum -y install trace-cmd
	rpm -q sysstat || yum -y install sysstat
	rpm -q strace || yum -y install strace
	rpm -q libcgroup || yum -y install libcgroup
	rpm -q libcgroup-tools || yum -y install libcgroup-tools
	rpm -q glibc-devel || yum -y install glibc-devel
	rpm -q gcc || yum -y install gcc
	rpm -q libgcc || yum -y install libgcc
	rpm -q gcc-c++ || yum -y install gcc-c++
	rpm -q gdb || yum -y install gdb
	rpm -q numactl || yum -y install numactl

	if [[ "$(uname -m)" = x86_64 ]];then
		rpm -q libgcc.i686 || yum -y install libgcc.i686 &>/dev/null
		rpm -q glibc-devel.i686  || yum -y install glibc-devel.i686  libgcc.i686 &>/dev/null
	fi
}

hugepage_support(){
	# memory reg suit support huge page
	cat /proc/filesystems |grep -i hugetlb
	local ret=$?
	return $ret
}

# Is  huage page supported? Numa supported?
get_feature(){
	M_RS_HUGEPAGE=0
	hugepage_support && M_RS_HUGEPAGE=1;
}

get_systeminfo(){
	echo "########pidstat#############"
	pidstat
	echo ""
	echo ""
	echo "########lscpu##############"
	lscpu
	echo ""

	echo "#######cpuinfo###############"
	cat /proc/cpuinfo
	echo ""

	echo "#######meminfo###############"
	cat /proc/meminfo
	echo ""

	echo "#######Vmstat###############"
	vmstat
	echo ""
}

function meminfo_check()
{
	rpm -q bc &>/dev/null || yum -y install bc &>/dev/null
	node_list=$(find /sys/devices/system/node/ -name meminfo -exec grep MemTotal {} \; | awk '{print $2}')
	nodeinfo() {
		local node=$1
		local field=$2
		find /sys/devices/system/node/node$1 -name meminfo -exec grep $field {} \; | awk '{print $4}'
	}
	for node in $node_list; do
		nmemtotal=$(nodeinfo $node MemTotal)
		nmemfree=$(nodeinfo $node MemFree)
		nmemused=$(nodeinfo $node MemUse)
		printf "Mmemory Node$node Total: %s Free: %s Used: %s\n" $nmemtotal $nmemfree $nmemused

		if [ "$nmemtotal" = "$nmemfree" ] && [ "$nmemused" = "$nmemtotal" ] && [ "$nmemtotal" = 0 ]; then
			printf "Node $node: No memory in Node$node !!\n"
			return 0
		fi
		if [ ! $(echo $nmemused \< $nmemtotal | bc) = "1" ] || [ ! $(echo $nmemfree \< $nmemtotal | bc) = "1" ]; then
			printf "Node $node: Wrong meminfo in Node$node\n"
			return 1
		fi
	done

	memtotal=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
	memfree=$(awk '/MemFree/ {print $2}' /proc/meminfo)
	memavai=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
	if [ ! $(echo $memfree \< $memtotal | bc) = "1" ] || [ ! $(echo $memavai \< $memtotal | bc) = "1" ]; then
		printf "Node $node: Wrong meminfo in /proc/meminfo"
		return 1
	fi
	printf "Memory SYS Total: %s Free: %s Avai: %s\n" $memtotal $memfree $memavai

	return 0
}

get_release()
{
	if rlIsRHEL; then
		for r in $(seq 5 100); do
			rlIsRHEL "$r" && RELEASE="rhel$r" && break
		done
	elif rlIsFedora; then
		for r in $(seq 25 100) ; do
			rlIsFedora "$r" && RELEASE="fedora$r" && break
		done
	fi
	[ -z "$RELEASE" ] && echo "ERROR: failed to get release" || echo "INFO: RELEASE=$RELEASE"
}

# compare two kernel version
function kvcmp()
{
	echo $1 $2 | awk '
	function cmp() {
		split($1,v1,"[.-]",seps1)
		split($2,v2,"[.-]",seps2)
		l=length(v1)>length(v2)?length(v1):length(v2)
		for(i=1;i<l;i++) {
			a1=0
			a2=0
			if (v1[i]~/[:alpha:]/)
				a1=-1
				if(v2[i]~/[:alpha:]/)
					a2=-1
					if (a1>a2||v1[i]>v2[i])
						return 1
					else if (a1<a2||v1[i]<v2[i])
						return 255
					}
					return 0
				}
				{
					exit cmp()
				}'
			}

# running kernel version is less or equal with the input version.
function kver_le()
{
	local v1=$1
	local v2=$(uname -r)

	kvcmp $v2 $v1
	local ret=$?
	((ret==0||ret==255))
	return $?
}

# running kernel version is greater or equal with the input version.
function kver_ge()
{
	local v1=$1
	local v2=$(uname -r)

	kvcmp $v2 $v1
	local ret=$?
	((ret==0||ret==1))
	return $?
}

get_release()
{
	local major=$(awk -F= '/^VERSION_ID=/ {gsub("\"","",$2);split($2,a,".");print a[1]}' /etc/os-release)
	local minor=$(awk -F= '/^VERSION_ID=/ {gsub("\"","",$2);split($2,a,".");print a[1]}' /etc/os-release)
	REL_ID=$(awk -F= '/^ID=/ {gsub("\"","",$2);print $2}' /etc/os-release)
	# rhel8 or fedora29
	RELEASE=${REL_ID}${major}
	# rhel83
	MINOR_RELEASE=${REL_ID}${major}
	echo "INFO: REL_ID=$REL_ID RELEASE=$RELEASE MINOR_RELEASE=$MINOR_RELEASE"
}

# Some bugs are skipped for some reasons.
mark_skip(){
	local bug="$1"
	local reason="$2"
	echo "$bug: $2" >> $FILE_SKIP_SUMMARY
	report_result "$bug" SKIP
}

# Get the skipped bugs
get_skip_summary(){
	echo "Summary of skipped bugs:"
	[ -f $FILE_SKIP_SUMMARY ] && cat $FILE_SKIP_SUMMARY
}

rebootdog_setup(){
	shopt -s expand_aliases
	# Feed the rebootdog, or it will bark when system restarted.
	alias rstrnt-reboot="rm -f $REBOOT_DOGFILE; rstrnt-reboot"
	alias reboot="rm -f $REBOOT_DOGFILE; reboot"
	grep -q reboot_dogfile /usr/bin/rstrnt-reboot  || sed -i '4irm \/mnt\/reboot_dogfile -f' /usr/bin/rstrnt-reboot
}

install_packages
get_systeminfo &>sysinfo.log
get_feature
rebootdog_setup
get_release
make module
