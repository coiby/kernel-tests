#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: TestCaseComment
#   Author: Wang Shu <shuwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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

function admin_reserve_kbytes_memhog()
{
    local free_memory
    rlRun "sysctl -w vm.drop_caches=3"
    free_memory=$(grep MemFree /proc/meminfo | awk '{print $2}')
    if [ $free_memory -lt 2000000 ]; then
        return 0
    fi

    # left 512m free memory for unprivileged users.
    rlRun "sysctl -w vm.admin_reserve_kbytes=$((free_memory-512*1024))"
    # rlRun "su ark_test -c 'memhog -r10 100m'"
    rlRun "su ark_test -c 'memhog -r10 1g'" 1-255


}

admin_reserve_kbytes()
{
    # reproducer for bz1413500, bz1413503
    local default_value=$(cat /proc/sys/vm/admin_reserve_kbytes)
    local total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')

    if rlIsRHEL ">=8" || rlIsFedora; then
        rlLogInfo "admin_reserve_kbytes is not supported any more since rhel9"
        rstrnt-report-result ${FUNCNAME[0]} SKIP
        return 0
    fi

    swapoff -a
    rlAssertGreaterOrEqual "Assert the default admin_reserve_kbytes is less or equal than 8192." 8192 ${default_value}
    rlRun "echo ${total_memory} > /proc/sys/vm/admin_reserve_kbytes"
    rlRun "useradd ark_test"
    rlRun "su ark_test -c 'ls -al ~'" 1-255       # this should fail since all memory is reserved for admins

    which memhog && admin_reserve_kbytes_memhog

    rlRun "echo ${default_value} > /proc/sys/vm/admin_reserve_kbytes"
    rlRun "userdel -rf ark_test"
    swapon -a
}

