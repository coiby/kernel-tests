#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#

kver_ret=0

# kvercmp '2.6.32-101.el6' '3.1.4-0.2.el7.x86_64'
# kvercmp '3.1.4-0.2.el7.x86_64' `uname -r`
function kvercmp()
{
	ver1=`echo $1 | sed 's/-/./'`
	ver2=`echo $2 | sed 's/-/./'`

	ret=0
	i=1
	while [ 1 ]; do
		digit1=`echo $ver1 | cut -d . -f $i`
		digit2=`echo $ver2 | cut -d . -f $i`

		if [ -z "$digit1" ]; then
			if [ -z "$digit2" ]; then
				ret=0
				break
			else
				ret=-1
				break
			fi
		fi

		if [ -z "$digit2" ]; then
			ret=1
			break
		fi

		if [ "$digit1" != "$digit2" ]; then
			if [ "$digit1" -lt "$digit2" ]; then
				ret=-1
				break
			fi
			ret=1
			break
		fi

		i=$((i+1))
	done
	kver_ret=$ret

	echo "kvercmp($1,$2): $kver_ret"
}

# Log a message to the ${DEBUGLOG} or to /dev/null.
debug ()
{
	local msg="$1"
	local timestamp=$(date +%Y%m%d-%H%M%S)
	if [ "${devnull:?}" = "0" ]; then
		lockfile -r 1 ${lck:?}
		if [ "$?" = "0" ]; then
			echo -n "${timestamp}: " >>$DEBUGLOG 2>&1
			echo "${msg}" >>$DEBUGLOG 2>&1
			rm -f ${lck:?} >/dev/null 2>&1
		fi
	else
		echo "${msg}" >/dev/null 2>&1
	fi
}

ipc_debug_info ()
{
	debug "******* Requested Information $1 *******"
	debug "** IPCS Information **"
	/usr/bin/ipcs -a >> $DEBUGLOG
	debug "** msgmni Information **"
	cat /proc/sys/kernel/msgmni >> $DEBUGLOG
	debug "******* End Requested Information $1 *******"

	# Just for easy reading
	echo >> $DEBUGLOG
	if [ "$1" = "After" ] || [ "$1" = "AfterIPCRMCleanUp" ]; then
		echo >> $DEBUGLOG
	fi
}

PrintSysInfo ()
{
	echo "uname -rm" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	hostname | tee -a $SYSINFO
	uname -rm | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	echo "lscpu" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	lscpu | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	echo "numactl --hardware" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	numactl --hardware | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	echo "cat /proc/cmdline" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	cat /proc/cmdline | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	echo "cat /proc/meminfo" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	cat /proc/meminfo | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	echo "lsblk" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	lsblk | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	echo "dmsetup table" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	dmsetup table | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	echo "df -Th" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	df -Th | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	echo "fdisk -l" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	fdisk -l | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	echo "mount | column -t" | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO
	mount | column -t | tee -a $SYSINFO
	echo "-----" | tee -a $SYSINFO

	cp -f $SYSINFO ./systeminfo.txt
	SubmitLog ./systeminfo.txt
}

# Setup desired filesystem mounted at /mnt/testarea
# TEST_DEV or TEST_MNT can be set, this useful when testing filesystems in beaker
#
# If TEST_DEV is set, mkfs on TEST_DEV and mount it at /mnt/testarea
# If TEST_MNT is set, grab device mounted at TEST_MNT first and mkfs & mount at
# /mnt/testarea
#
# Also MKFS_OPTS and MOUNT_OPTS can be set to specify mkfs and mount options, e.g.
# FSTYP=xfs MKFS_OPTS="-m crc=1" MOUNT_OPTS="-o relatime"  bash ./runtest
setup_testarea()
{
	if [ "${TEST_DEV}" != "" ] || [ "${TEST_MNT}" != "" ]; then
		echo "============ Setup /mnt/testarea ============"
		if [ "${FSTYP}" == "" ]; then
			echo " - Having TEST_DEV or TEST_MNT set but not FSTYP" | tee -a $OUTPUTFILE
			exit 1
		fi
		if [ "${TEST_MNT}" != "" ]; then
			dev=`grep "${TEST_MNT}" /proc/mounts | awk '{print $1}'`
			if [ -z $dev ]; then
				echo " - TEST_MNT set to ${TEST_MNT}, but no partition mounted there" | tee -a $OUTPUTFILE
				exit 1
			fi
			cp /etc/fstab{,.bak}
			grep -v ${TEST_MNT} /etc/fstab.bak >/etc/fstab
			umount ${TEST_MNT}
		fi
		if [ "$dev" == "" ] && [ "${TEST_DEV}" != "" ]; then
			dev="$TEST_DEV"
		fi
		if [ "$dev" == "" ]; then
			echo " - No suitable test device found" | tee -a $OUTPUTFILE
			exit 1
		fi
		if [ "${FSTYP}" == "xfs" ] || [ "${FSTYP}" == "btrfs" ]; then
			mkfs -t ${FSTYP} ${MKFS_OPTS} -f $dev
		elif [ "${FSTYP}" == "overlayfs" ]; then
			mkfs -t xfs -n ftype=1 -f $dev
		else
			mkfs -t ${FSTYP} ${MKFS_OPTS} $dev
		fi
		if [ $? -ne 0 ]; then
			echo " - mkfs failed" | tee -a $OUTPUTFILE
			exit 1
		fi
		if [ "$FSTYP" == "overlayfs" ]; then
			mkdir -p /mnt/ltp-overlay
			mount ${MOUNT_OPTS} $dev /mnt/ltp-overlay
			mkdir -p /mnt/ltp-overlay/lower
			mkdir -p /mnt/ltp-overlay/upper
			mkdir -p /mnt/ltp-overlay/workdir
			mount -t overlay overlay -olowerdir=/mnt/ltp-overlay/lower,upperdir=/mnt/ltp-overlay/upper,workdir=/mnt/ltp-overlay/workdir /mnt/testarea
		else
			mount ${MOUNT_OPTS} $dev /mnt/testarea
		fi
		if [ $? -ne 0 ]; then
			echo " - mount $dev at /mnt/testarea failed" | tee -a $OUTPUTFILE
			exit 1
		fi
	fi
}

# by jstancek
check_cpu_cgroup ()
{
	# Move us to root cpu cgroup
	# see: Bug 773259 - tests don't run in root cpu cgroup with systemd

	cgroup2_mntpoint=$(mount | grep ^cgroup2 | awk '{print $3}')
	if [ -n "$cgroup2_mntpoint" ]; then
		echo "Found cgroup2 mount point, moving pid $$ to $cgroup2_mntpoint/cgroup.procs"
		echo $$ > $cgroup2_mntpoint/cgroup.procs
		return
	fi

	cpu_cgroup_mntpoint=$(mount | grep "type cgroup (.*cpu[,)]" | awk '{print $3}')

	[ -d $cpu_cgroup_mntpoint/system.slice/ ] || mkdir -p $cpu_cgroup_mntpoint/system.slice/
	cat $cpu_cgroup_mntpoint/cpu.rt_runtime_us > $cpu_cgroup_mntpoint/system.slice/cpu.rt_runtime_us

	cpu_path=$(cat /proc/self/cgroup | grep ":cpu[:,]" | sed "s/.*://")
	cat $cpu_cgroup_mntpoint/cpu.rt_runtime_us > $cpu_cgroup_mntpoint/$cpu_path/cpu.rt_runtime_us

	if [ -e /proc/self/cgroup ]; then
		grep -i "cpu[,:]" /proc/self/cgroup | grep -q ":/$"
		ret=$?
	else
		echo "Couldn't find /proc/self/cgroup." | tee -a $OUTPUTFILE
		ret=1
	fi

	if [ $ret -eq 0 ]; then
		echo "Running in root cpu cgroup" | tee -a $OUTPUTFILE
	else
		echo "cat /proc/self/cgroup" | tee -a $OUTPUTFILE
		cat /proc/self/cgroup | tee -a $OUTPUTFILE
		if [ -e "$cpu_cgroup_mntpoint/tasks" ]; then
			echo "Found root cpu cgroup tasks at: $cpu_cgroup_mntpoint/tasks" | tee -a $OUTPUTFILE
			echo $$ > $cpu_cgroup_mntpoint/tasks
			# shellcheck disable=SC2320
			ret=$?
			if [ $ret -eq 0 ]; then
				echo "Succesfully moved (pid: $$) to root cpu cgroup." | tee -a $OUTPUTFILE
			else
				echo "Failed to move (pid: $$), ret code: $ret" | tee -a $OUTPUTFILE
			fi
		fi

		if [ $ret -ne 0 ]; then
			echo "Couldn't verify that we run in root cpu cgroup." | tee -a $OUTPUTFILE
			echo "Note that some tests (on RHEL7) may fail, see Bug 773259." | tee -a $OUTPUTFILE
		fi
	fi
}

ipcrm_cleanup ()
{
	# Clean up msgid
	debug "******* Start msgmni cleanup *******"
	for i in `ipcs -q | cut -f2 -d' '`; do
		ipcrm -q $i
	done
	debug "******* End msgmni cleanup *******"
	echo >> $DEBUGLOG
}

check_time ()
{
	local timestamp=$(date '+%F %T')
	logger -p local0.notice -t TEST.INFO: "$timestamp -> $1"
}

EnableNTP ()
{
	local timestamp=$(date '+%F %T')
	logger -p local0.notice -t TEST.INFO: "$timestamp -> Enable NTP"
	# service ntpd start
}

DisableNTP ()
{
	local timestamp=$(date '+%F %T')
	logger -p local0.notice -t TEST.INFO: "$timestamp -> Disable NTP"
	# service ntpd stop
}

# Workaround for Bug 1263712 - OOM is sporadically killing more than just expected process
protect_harness_from_OOM()
{
	for pid in $(pgrep systemd) $(pgrep restraintd) $(pgrep beah) $(pgrep rhts) $(pgrep ltp) $(pgrep dhclient) $(pgrep NetworkManager); do
		echo -16 > /proc/$pid/oom_adj
	done

	# make sure children of this process are not protected
	# as those include also OOM tests
	echo 0 > /proc/self/oom_adj
}

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
	check_cpu_cgroup
fi
