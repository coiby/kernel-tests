#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Author: Li Wang <liwang@redhat.com>
# bz1373519

function bz1373519()
{
	local ori_shmmni=$(cat /proc/sys/kernel/shmmni)

	rlRun "echo 0 > /proc/sys/kernel/shmmni"
	rlAssertEquals "Assert 0 shmmni" `cat /proc/sys/kernel/shmmni` 0

	rlRun "echo 32768 >/proc/sys/kernel/shmmni"
	rlAssertEquals "Assert 32768 shmmni" `cat /proc/sys/kernel/shmmni` 32768

	echo 32769 >/proc/sys/kernel/shmmni
	[ $? -ne 0 ] && rlLog "PASS: Assert 32769 shmmni is Invalid argument"

	echo $ori_shmmni >/proc/sys/kernel/shmmni

	return 0
}
