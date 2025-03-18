#!/bin/bash
function bz1912221()
{
	# first reboot and second reboot.
	local rebootflag_f=${DIR_DEBUG}/REBOOT_${FUNCNAME}_F
	local rebootflag_s=${DIR_DEBUG}/REBOOT_${FUNCNAME}_S

	uname -a | grep x86 || { report_result $FUNCNAME SKIP; return; }

	if [ -f "$rebootflag_s" ];then
		rlAssertNotGrep "console=ttyS0" /proc/cmdline "-E"
		[ $? -ne 0 ] && rlLogInfo "Commandline has been reset to normal $(cat /proc/cmdline)"
		return 0;
	fi

	if [ ! -f "$rebootflag_f" ];then
		if ! grep "console=ttyS0" /proc/cmdline; then
			rlRun "grubby --args console=ttyS0,115200n81 --update-kernel DEFAULT"
			touch $rebootflag_f
			rstrnt-reboot
		else
			# Sometimes dd soft lockup, but that's not bug but load too heavy
			$DIR_SOURCE/bz1912221_run_in_serial.sh &
			sleep 5
			pkill dd
			for i in $(seq 1 10); do
				ps -C dd --no-headers && pkill dd
				sleep 5
			done
			ps -C dd --no-headers  && report_result cleanup WARN
		fi
	else
		$DIR_SOURCE/bz1912221_run_in_serial.sh &
		sleep 5
		pkill dd
		for i in $(seq 1 10); do
			ps -C dd --no-headers && pkill dd
			sleep 5
		done
		ps -C dd --no-headers  && report_result cleanup WARN
		# set the kernel cmdline to the default.
		rlRun "grubby --remove-args console=ttyS0,115200n81 --update-kernel DEFAULT"
		rlLogInfo "$FUNCNAME: reboot the machine"
		rlRun "touch $rebootflag_s"
		rstrnt-reboot
	fi
}
