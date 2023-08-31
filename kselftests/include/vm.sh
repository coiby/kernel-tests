#!/bin/bash
cmd_selinux=$(grep selinux /proc/cmdline)
cmd_enforcing=$(grep enforcing /proc/cmdline)
do_vm_config()
{
    if [[ -n ${cmd_selinux} || -n ${cmd_enforcing} ]]; then
        rlLog "cannot override /proc/cmdline selinux policy settings."
    else
        rlRun "setenforce 0"
    fi
}

do_vm_reset()
{
    if [[ -n ${cmd_selinux} ||  -n ${cmd_enforcing} ]]; then
        rlLog "cannot override /proc/cmdline selinux policy settings."
    else
        rlRun "setenforce 1"
    fi
}
