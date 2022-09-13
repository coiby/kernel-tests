#!/bin/bash
export DIR_ENTRY=$(pwd)
export DIR_DEBUG=$DIR_ENTRY/debug
export REBOOT_DOGFILE="/mnt/reboot_dogfile"

FILE_SKIP_SUMMARY="$DIR_DEBUG/skipped_bugs_summary.txt"

install_packages(){
	rpm -q perf || yum -y install perf
	rpm -q trace-cmd || yum -y install trace-cmd
	rpm -q sysstat || yum -y install sysstat
	rpm -q strace || yum -y install strace
	rpm -q libcgroup || yum -y install libcgroup
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

get_release()
{
	local major=$(awk -F= '/^VERSION_ID=/ {gsub("\"","",$2);split($2,a,".");print a[1]}' /etc/os-release)
	local id=$(awk -F= '/^ID=/ {gsub("\"","",$2);print $2}' /etc/os-release)
	# rhel8 or fedora29
	RELEASE=${id}${major}
	echo "INFO: RELEASE=$RELEASE"
}

# Some bugs are skipped for some reasons.
mark_skip(){
	local bug="$1"
	local reason="$2"
	echo "$bug: $2" >> $FILE_SKIP_SUMMARY
}

# Get the skipped bugs
get_skip_summary(){
	echo "Summary of skipped bugs:"
	[ -f $FILE_SKIP_SUMMARY ] && cat $FILE_SKIP_SUMMARY
}

rebootdog_setup(){
	shopt -s expand_aliases
	# Feed the rebootdog, or it will bark when system restarted.
	alias rhts-reboot="rm -f $REBOOT_DOGFILE; rhts-reboot"
	alias reboot="rm -f $REBOOT_DOGFILE; reboot"
	grep -q reboot_dogfile /usr/bin/rhts-reboot  || sed -i '4irm \/mnt\/reboot_dogfile -f' /usr/bin/rhts-reboot
}

install_packages
get_systeminfo &>sysinfo.log
get_feature
rebootdog_setup
make module
get_release
