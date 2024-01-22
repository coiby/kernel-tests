#!/bin/bash

export DIR_ENTRY=$(pwd)
export DIR_DEBUG=$DIR_ENTRY/debug

# unset bkr env ARCH to avoid name conflict with
# kernel module building.
unset ARCH

FILE_SKIP_SUMMARY="$DIR_DEBUG/skipped_bugs_summary.txt"

function install_libcgroup()
{
	local pkg=libcgroup.20210106.tgz
	[ -z "$LOOKASIDE" ] && LOOKASIDE=http://download.devel.redhat.com/qa/rhts/lookaside/
	which cgcreate &>/dev/null && return 0
	which cgcreate &>/dev/null || yum -y install libcgroup-tools &>/dev/null
	which cgcreate  && return 0

	rpm -q cmake || yum -y install cmake &>/dev/null
	rpm -q pam-devel || yum -y install pam-devel bison flex
	curl -LkO  $LOOKASIDE/$pkg || return 1
	tar -zxf $pkg
	pushd libcgroup
	sh bootstrap.sh
	make install -j $(nproc)
	popd
}

install_packages(){
	if [[ "$(uname -m)" = x86_64 ]];then
		rpm -q libgcc.i686 || yum -y install libgcc.i686 &>/dev/null
		rpm -q glibc-devel.i686  || yum -y install glibc-devel.i686  libgcc.i686 &>/dev/null
	fi
	rpm -q perf || yum -y install perf
	rpm -q trace-cmd || yum -y install trace-cmd
	rpm -q sysstat || yum -y install sysstat
	rpm -q strace || yum -y install strace
	rpm -q libcgroup || yum -y install libcgroup
	rpm -q numactl || yum -y install numactl
	install_libcgroup
	rpm -q elfutils-libelf-devel || yum -y install elfutils-libelf-devel > /dev/null
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
	# shellcheck disable=SC2034
	hugepage_support && M_RS_HUGEPAGE=1;
}

get_systeminfo(){
	echo "#######meminfo###############"
	cat /proc/cmdline
	echo ""

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

# Some bugs are skipped for some reasons.
mark_skip(){
	local bug="$1"
	local reason="$2"
	echo "$bug: $reason" >> $FILE_SKIP_SUMMARY
}

# Get the skipped bugs
get_skip_summary(){
	echo "Summary of skipped bugs:"
	[ -f $FILE_SKIP_SUMMARY ] && cat $FILE_SKIP_SUMMARY
}

setup_cmdline_args(){
	if [ -f $DIR_DEBUG/SETUPDONEFLAG_"$2"_DONE ]; then
		return 1
	fi
	if [ -f $DIR_DEBUG/SETUPDONEFLAG_"$2" ]; then
		mv $DIR_DEBUG/SETUPDONEFLAG_"$2" $DIR_DEBUG/SETUPDONEFLAG_"$2"_DONE
		return 0
	fi

	echo "Setup cmdline args: $1"
	grubby --args="$1" --update-kernel="$(grubby --default-kernel)"
	if [ "$(uname -m)" = "s390x" ]; then
		zipl
	fi
	touch $DIR_DEBUG/SETUPDONEFLAG_"$2"
	rhts-reboot
	sleep 100000
}

cleanup_cmdline_args(){
	echo "Cleanup cmdline args: $1"
	grubby --remove-args="$1" --update-kernel="$(grubby --default-kernel)"
	if [ "$(uname -m)" = "s390x" ]; then
		zipl
	fi
	rm -vf $DIR_DEBUG/SETUPDONEFLAG_*
	touch $DIR_DEBUG/REBOOTAFTERDONE
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
	MINOR_RELEASE=${REL_ID}${major}${minor}
	echo "INFO: REL_ID=$REL_ID RELEASE=$RELEASE MINOR_RELEASE=$MINOR_RELEASE"
}

function check_knownissues()
{
	local i
	local subfunc=${1}
	# shellcheck disable=SC2048
	if echo ${KNOWN_ISSUE_LIST[*]} | grep -q $subfunc; then
		local bug_id=$(echo ${KNOWN_ISSUE_LIST[$REL_ID]} | awk -F: -v RS=' ' '/'$subfunc'/ {split($2,a,",");print a[1]}')
		# Array elements
		# shellcheck disable=SC2207
		local kver_since=($(echo "${KNOWN_FILED_BUGS[$bug_id]}" | awk -v RS=' ' '{split($0,a,"->");print a[1]}'))
		# shellcheck disable=SC2207
		local kver_until=($(echo "${KNOWN_FILED_BUGS[$bug_id]}" | awk -v RS=' ' '{split($0,a,"->");print a[2]}'))
		for ((i=0; i<${#kver_since[*]}; i++)); do
			if kver_ge ${kver_since[$i]}; then
				if [ "${kver_until[$i]}" = "*" ] || kver_le "${kver_until[$i]}"; then
					echo "$subfunc: Switching test phase to warning, as there's knownissue $bug_id"
					export ptype=WARN
					export pname=${subfunc}_$(echo ${KNOWN_ISSUE_LIST[$REL_ID]} |\
					awk -F: -v RS=' ' '/'$subfunc'/ {if (NF>1) {gsub(",","-unfix",$2);\
					printf("unfix%s",$2)} else {printf("%s", $1)} exit 0}')
					return 0
				fi
			fi
		done
	fi
	return 1
}
function test_get_diskfreek()
{
	local free_k=$(df -k . | awk '/Filesystem/ {for (i=1; i<=NF; i++) if ($i == "Available") avail=i;next;} {print $avail}')
	echo $free_k | grep -vE "[^0-9]+"
}

function test_get_diskfreem()
{
	local free_m=$(df -m . | awk '/Filesystem/ {for (i=1; i<=NF; i++) if ($i == "Available") avail=i;next;} {print $avail}')
	echo $free_m | grep -vE "[^0-9]+"
}


install_packages
get_systeminfo &>sysinfo.log
get_feature
get_release
