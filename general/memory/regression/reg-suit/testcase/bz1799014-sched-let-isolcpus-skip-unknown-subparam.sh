function bz1799014()
{
	local flag=/mnt/${FUNCNAME}
	! test -f $flag && touch $flag && echo 0 > $flag
	local val=$(cat $flag)
	local nr=$(nproc)

	if ! rlIsRHEL ">=8.2"; then
		echo "Skip $FUNCNAME test"
		return
	fi

	if [ "$nr" -lt 2 ]; then
		echo "Skip $FUNCNAME test"
		return
	fi

	if [ "$val" = 0 ]; then
		rlRun "grubby --args isolcpus=doMain,nohz,Domian,1 --update-kernel DEFAULT"
		echo 1 > $flag
		rhts-reboot
	elif [ "$val" = 1 ]; then
		rlRun "journalctl -kb --no-hostname | grep isolcpus | grep 'Skipped unknown flag doMain'"
		echo 2 > $flag
		rhts-reboot
	elif [ "$val" = 2 ]; then
		echo 3 > $flag
		rlRun "grubby --remove-args isolcpus=doMain,nohz,Domian,1 --update-kernel DEFAULT"
		rhts-reboot
	else
		rm -f $flag
		return
	fi
}
