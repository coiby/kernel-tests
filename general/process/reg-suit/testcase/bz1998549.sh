#!/bin/bash
function bz1998549()
{
	if uname -r | grep mr && ! uname -r | grep x86_64; then
		report_result "${FUNCNAME}_module_compile" SKIP
		return
	fi
	if uname -r | grep -e rt -e debug -q; then
		report_result "${FUNCNAME}_kernel_rt" SKIP
		return
	fi
	unset ARCH

	local exp_ret=0
	# in rhel9 & x86_64, preempt rcu is enabled, rcu_read_unlock is GPL only, while in rhel8, it's not
	if grep "CONFIG_PREEMPT_RCU=y" /boot/config-$(uname -r); then
		exp_ret=1-255
	fi
	rlRun "cd $DIR_MODULE"
	rlRun "make" $exp_ret
	rlRun "cd -"
	rlRun "test -f $DIR_MODULE/${FUNCNAME}.ko" $exp_ret
}
