#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: TestCaseComment
#   Author: Wang Shu <shuwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~



function shmall_shmmax_shmmni_backup()
{
    SHMALL=$(sysctl -n kernel.shmall)
    SHMMAX=$(sysctl -n kernel.shmmax)
    SHMMNI=$(sysctl -n kernel.shmmni)
    SHMRMID=$(sysctl -n kernel.shm_rmid_forced)
}

function shmall_shmmax_shmmni_restore()
{
    rlRun "sysctl kernel.shmall=$SHMALL"
    rlRun "sysctl kernel.shmmax=$SHMMAX"
    rlRun "sysctl kernel.shmmni=$SHMMNI"
    rlRun "sysctl kernel.shm_rmid_forced=$SHMRMID"
}

shmall_shmmax_shmmni_test()
{
    local SHM_PAGE_SIZE=`getconf PAGE_SIZE`
    local PAGE_IN_100MB=`expr 104857600 / $SHM_PAGE_SIZE`
    local SIZE_15MB=15728640
    local randoms=($(shuf -i 1-100000 -n 10))
    rlRun "gcc $DIR_SOURCE/shmtest.c -o ./shmtest"

    # prepare, setup global shared memory 100mb, max alloc 15mb,
    rlRun "sysctl kernel.shmall=$PAGE_IN_100MB"
    rlRun "sysctl kernel.shmmax=$SIZE_15MB"
    rlRun "sysctl kernel.shmmni=0"
    rlRun "sysctl kernel.shmmni=32768"
    rlRun "sysctl kernel.shm_rmid_forced=0"
    rlRun "echo request 90mb shared memory"

    # alloc 90mb shared memory
    rlRun "./shmtest $((randoms[0])) $SIZE_15MB"
    rlRun "./shmtest $((randoms[1])) $SIZE_15MB"
    rlRun "./shmtest $((randoms[2])) $SIZE_15MB"
    rlRun "./shmtest $((randoms[3])) $SIZE_15MB"
    rlRun "./shmtest $((randoms[4])) $SIZE_15MB"
    rlRun "./shmtest $((randoms[5])) $SIZE_15MB"

    # expected failure
    rlRun "! ./shmtest $((randoms[6])) $SIZE_15MB"

    # release shared memory
    rlRun "sysctl kernel.shm_rmid_forced=1"

    # boundary test for shmall & shmmax
    rlRun "./shmtest $((randoms[7])) $SIZE_15MB"
    rlRun "! ./shmtest $((randoms[8])) `expr $SIZE_15MB + 1`"

    rlRun "sysctl kernel.shmall=0"
    rlRun "! ./shmtest $((randoms[9])) 1"


}

shmall_shmmax_shmmni()
{
    rlAssertExists /proc/sys/kernel/shmall
    rlAssertExists /proc/sys/kernel/shmmax
    rlAssertExists /proc/sys/kernel/shmmni
    rlAssertExists /proc/sys/kernel/shm_rmid_forced

    shmall_shmmax_shmmni_backup
    shmall_shmmax_shmmni_test
    shmall_shmmax_shmmni_restore
}
