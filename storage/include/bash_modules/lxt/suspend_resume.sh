#!/bin/bash

function suspend_resume ()
{
	if [ $# -lt 2 ]; then
		echo "Usage: suspend_resume mem|disk 180 test_dev(optional)"
		exit 1
	fi
	local mode=${1:-"mem"}
	local seconds=${2:-"180"}

	while [ $# -ge 3 ]; do
		local test_dev="/dev/$3"
		local iodepth=64
		local runtime=240
		local t_size=1g
		local numjobs=64
		tlog "Will start fio write/randwrite/read/randread test with $test_dev"
		tok "fio -filename=$test_dev -iodepth=$iodepth -thread -rw=randwrite -ioengine=libaio -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=$runtime -time_based -size=$t_size -group_reporting -name=mytest -numjobs=$numjobs" &
		shift
	done

	sleep 5
	tlog "Will enter to rtcwake:$mode mode and resume after $seconds seconds"
	tok "rtcwake -m $mode -s $seconds"
	wait
}

function prepare_reboot()
{
	# IA-64 needs nextboot set.
	if [ -e "/usr/sbin/efibootmgr" ]; then
		EFI=$(efibootmgr -v | grep BootCurrent | awk '{ print $2}')
		if [ -n "$EFI" ]; then
			tlog "Updating efibootmgr next boot option to $EFI according to BootCurrent"
			tok "efibootmgr -n $EFI"
		elif [[ -z "$EFI" && -f /root/EFI_BOOT_ENTRY.TXT ]] ; then
			os_boot_entry=$(</root/EFI_BOOT_ENTRY.TXT)
			tlog "Updating efibootmgr next boot option to $os_boot_entry according to EFI_BOOT_ENTRY.TXT"
			tok "efibootmgr -n $os_boot_entry"
		else
			tlog "Could not determine value for BootNext!"
		fi
	fi
}

function add_kernel_option ()
{
	#add no_console_suspend to kernel options
	tok "grubby --args=\"no_console_suspend=1 loglevel=8\" --update-kernel=ALL"
	rhts-reboot
}
