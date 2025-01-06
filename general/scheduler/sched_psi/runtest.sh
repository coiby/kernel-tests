#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/schedular/sched_psi
#   Description: check if PSI works
#   Author: Mingrui Zhang <mizhang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

. /usr/share/beakerlib/beakerlib.sh || exit 1

#python
if rlIsRHEL ">=8"; then
    PYTHON="/usr/libexec/platform-python"
else
    PYTHON="python"
fi
#kernel
DEFAULT_KERNEL=`grubby --default-kernel`


function Install_stress_ng(){
    yum install -y kernel-general-include
    rlRun "cd /mnt/tests/kernel/general/include/scripts" 0 ""
    rlRun "./stress.sh" 0 "install stress-ng"
    rlRun "cd -" 0 "cd -"
}

function Plain_psi_test(){
    export PSI_TEST_OPTION_TASK_NAME="io"
    export PSI_TEST_OPTION_CG="nocg2"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi io test"

    export PSI_TEST_OPTION_TASK_NAME="memory"
    export PSI_TEST_OPTION_CG="nocg2"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi memory test"

    export PSI_TEST_OPTION_TASK_NAME="cpu"
    export PSI_TEST_OPTION_CG="nocg2"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi cpu test"
}

function create_cg2(){
    rlRun "mkdir /mnt/cgroup2" 0 "Create mount point"
    rlRun "mount -t cgroup2 none /mnt/cgroup2" 0 "Create cgroup"
    rlRun "echo '+cpu +memory +io' > /mnt/cgroup2/cgroup.subtree_control" 0 "set subtree control"
}

function create_cg2_sub(){
    rlRun "mkdir /mnt/cgroup2/sub1" 0 "make subtree1"
    rlRun "mkdir /mnt/cgroup2/sub2" 0 "make subtree2"
}

function cg2_psi_test(){
    export PSI_TEST_OPTION_TASK_NAME="io"
    export PSI_TEST_OPTION_CG="cg2"
    export PSI_TEST_OPTION_CG_PATH="/mnt/cgroup2/sub1"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi io test in cg sub1"
    export PSI_TEST_OPTION_CG_PATH="/mnt/cgroup2/sub2"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi io test in cg sub2"

    export PSI_TEST_OPTION_TASK_NAME="memory"
    export PSI_TEST_OPTION_CG="cg2"
    export PSI_TEST_OPTION_CG_PATH="/mnt/cgroup2/sub1"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi memory test in cg sub1"
    export PSI_TEST_OPTION_CG_PATH="/mnt/cgroup2/sub2"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi memory test in cg sub2"

    export PSI_TEST_OPTION_TASK_NAME="cpu"
    export PSI_TEST_OPTION_CG="cg2"
    export PSI_TEST_OPTION_CG_PATH="/mnt/cgroup2/sub1"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi cpu test in cg sub1"
    export PSI_TEST_OPTION_CG_PATH="/mnt/cgroup2/sub2"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi cpu test in cg sub2"

}

function cg2_parallel(){
    export PSI_TEST_OPTION_TASK_NAME="io"
    export PSI_TEST_OPTION_CG="cg2_p"
    export PSI_TEST_OPTION_CG1_PATH="/mnt/cgroup2/sub1"
    export PSI_TEST_OPTION_CG2_PATH="/mnt/cgroup2/sub2"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi io test in cg sub1"

    export PSI_TEST_OPTION_TASK_NAME="memory"
    export PSI_TEST_OPTION_CG="cg2_P"
    export PSI_TEST_OPTION_CG1_PATH="/mnt/cgroup2/sub2"
    export PSI_TEST_OPTION_CG2_PATH="/mnt/cgroup2/sub1"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi memory test in cg sub2"

    export PSI_TEST_OPTION_TASK_NAME="cpu"
    export PSI_TEST_OPTION_CG="cg2_p"
    export PSI_TEST_OPTION_CG1_PATH="/mnt/cgroup2/sub1"
    export PSI_TEST_OPTION_CG2_PATH="/mnt/cgroup2/sub2"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi cpu test in cg sub1"
}

function Trigger(){
    rlRun "gcc source/trigger.c -o source/trigger" 0 "compile trigger file"
    unset PSI_TEST_OPTION_CG2_PATH
    export PSI_TEST_OPTION_CG="trigger"
    rlRun "$PYTHON ./source/test_psi.py" 0 "Run psi trigger test in cgroup root, cgroup subtree"
}

function s390_zipl()
{
    uname -m | grep -q s390 && zipl
}


rlJournalStart
    rlPhaseStartTest
    test -f status || { touch status; echo 0 > status; }
    grep CONFIG_PSI=y /boot/config-$(uname -r) && support=1 || support=0
    status=$(cat status)

    if [ $support -eq 1 ] && [ $status -eq 0 ]; then
        rlLogInfo "Set PSI"
        rlRun "grubby --args='psi=1 cgroup_no_v1=all' --update-kernel=$DEFAULT_KERNEL" 0 "Add kernel boot options: psi=1, cgroup_no_v1=all"
        s390_zipl
        echo 1 > status
        rlRun "rstrnt-reboot" 0 "Reboot"
    elif [ $support -eq 1 ] && [ $status -eq 1 ]; then
        rpm -q gcc || yum install -y gcc
        rlAssertGrep 'psi=1' /proc/cmdline || rlDie "no psi=1 in cmdline..."
        rlLogInfo "PSI Enabled"
        Install_stress_ng
        rlRun "gcc source/mem_stress.c -o source/mem_stress" 0 "compile mem_stress program"
        create_cg2
        create_cg2_sub
        Plain_psi_test
        cg2_psi_test
        cg2_parallel
        Trigger
        echo 2 > status
        rlRun "rstrnt-reboot" 0 "Reboot"
    elif [ $support -eq 1 ] && [ $status -eq 2 ]; then
        rlLogInfo "Clean up started"
        rlRun "grubby --remove-args='psi=1 cgroup_no_v1=all' --update-kernel=$DEFAULT_KERNEL" 0 "Remove kernel boot options: psi=1, cgroup_no_v1=all"
        s390_zipl
        rlRun "rm -rf /mnt/cgroup2/" 0 "remove mount point"
        rlLogInfo "Clean up Finished"
        echo 3 > status
        rlRun "rstrnt-reboot" 0 "Reboot to clean cgroup"
    elif [ $support -eq 1 ] && [ $status -eq 3 ]; then
        rlReport "PSI test finised." "PASS"
    elif [ $support -eq 0 ]; then
        rlReport "PSI not available." "PASS"
    fi
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd

