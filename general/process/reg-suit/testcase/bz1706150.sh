#!/bin/bash
function bz1706150()
{
	local segvpid
	local parser=$DIR_SOURCE/bz1706150.pacct.pl
	chmod +x $parser
	rpm -q psacct || yum install psacct -y

	rlServiceStart psacct

	sleep 30 &
	segvpid=$!

	echo "setvpid:$segvpid runtest.sh:pid: $$"

	sleep 1

	ps -p $segvpid -o pid,flags,comm
	kill -SIGSEGV $segvpid

	sleep 1
	ps -p $segvpid -o pid,flags,comm

	sleep 5

	cat /var/account/pacct | $parser | grep $segvpid
	local pacct_flag=$(cat /var/account/pacct | $parser | grep $segvpid | awk '{print $7}')
	# 1 is for PF_FORKNOEXEC, met once it set in 8.2, it's either the segvpid is wrong
	# or the acct is wrong.
	#rlAssertEquals "current->flags should be"  "18" "$((pacct_flag & ~1))"
	rlAssertEquals "current->flags should be"  "18" "$((pacct_flag))"

	rlServiceRestore psacct
}
