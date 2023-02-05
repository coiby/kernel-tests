#!/bin/sh

# Copyright (c) 2018 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#  Author: Xiaowu Wu    <xiawu@redhat.com>
#  Update: Ruowen Qin   <ruqin@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1322621 - Kdump rebuild will fail immediately if boot dir is readonly
# Bug is fixed in RHEL-7.3 kexec-tools-2.0.7-44.el7
CheckSkipTest kexec-tools 2.0.7-44 && Report

RegressionTest() {
    local kdump_bootdir="/boot"

    # Bug 1918499 - if /boot not writable, initramfs will be created in /var/lib/kdump
    # Bug is fixed in RHEL-8.5 on kexec-tools-2.0.20-52.el8
    # Since RHEL-8.5, Kdump will reset bootdir to /var/lib/kdump if /boot is not writableß
    CheckSkipTest kexec-tools 2.0.20-52 'checkonly' || {
        kdump_bootdir="/var/lib/kdump"
        Log "Expect kdump initramfs to be created in ${kdump_bootdir}"
    }

    # Backup kdump config
    cp -f "${KDUMP_CONFIG}" kdump_config_bk
    local boot_permission="rw"
    if ! mount | grep /boot | egrep -q 'rw|ro'; then
        Warn "System doesn't have the /boot partition."
        return
    else
        boot_permission="mount | grep /boot | egrep -o 'rw|ro'"
    fi

    # Remount /boot as RO
    if [ "$boot_permission" != 'ro' ]; then
        mount -o remount,ro /boot || {
            Warn "Failed to remount /boot as RO."
            return
        }
    fi

    # Test #1 - /boot is RO and force_no_rebuild is off (Default)
    local test_name="Test1 - /boot is RO and force_no_rebuild is off"
    local test_log="kdump_restart_force_no_rebuild_off.log"
    local test_result=0

    Log "$test_name"
    AppendConfig "force_no_rebuild 0"

    # Expect kdumpctl restart fail and no attempt to rebuild kdump inird img.
    touch ${KDUMP_CONFIG}
    LogRun "kdumpctl restart > ${test_log} 2>&1"
    retval="${PIPESTATUS[0]}"
    RhtsSubmit "$(pwd)/${test_log}"

    local err_msg_expect_fail="Expect kdump restart fail as boot dir is RO and not rebuild kdump img. But it didn't. Please check ${test_log}."
    local err_msg_exepct_pass="Expect kdump restart succeed and kdump img is saved in ${kdump_bootdir}. But it didn't. Please check ${test_log}."

    if [ "${kdump_bootdir}" == "/boot" ]; then
        if [ "${retval}" -eq 0 ] ||
            ! grep -q "does not have write permission.*not rebuild.*\.img" ${test_log}; then
            Error "${err_msg_expect_fail}"
        else
            Log "Test Pass"
            test_result=0
        fi
    elif [ "${kdump_bootdir}" == "/var/lib/kdump" ]; then
        # If fadump is enabled, still expect kdumpctl restart to fail. Otherwise kdump img will be saved to /var/lib/kdump
        if [ "${retval}" -ne 0 ]; then
            # if fadump on, expect kdumpctl restart still fail
            if grep -q "fadump=on" /proc/cmdline; then
                # Note error message is "Cannot reuild" for fadump, "Can not rebuild" for kdump
                if grep -q "does not have write permission.*not rebuild.*\.img" ${test_log}; then
                    Log "[fadump enabled] fadump restart failed as expected."
                    Log "Test Pass"
                    test_result=0
                else
                    Error "[fadump enabled] ${err_msg_expect_fail}"
                fi
            else
                Error "${err_msg_exepct_pass}"
            fi
        # The image should be generated in /var/lib/kdump folder
        elif ! grep -q "kdump: Rebuilding ${kdump_bootdir}" ${test_log}; then
            Error "${err_msg_exepct_pass}"
        else
            Log "Test Pass"
            test_result=0
        fi
    fi
    Report "${test_name}"
    test_result=$error
    error=0

    # Test #2 - /boot is RO and force_no_rebuild is on
    test_name="Test2 - /boot is RO and force_no_rebuild is on"
    test_log=/tmp/kdump_restart_force_no_rebuild_on.log

    Log "${test_name}"
    AppendConfig "force_no_rebuild 1"

    # Expect kdumpctl restart succeed and kdump initrd img is not rebuilt.
    LogRun "kdumpctl restart > ${test_log} 2>&1"
    retval=${PIPESTATUS[0]}
    RhtsSubmit "${test_log}"

    if [ "${retval}" -ne 0 ] || grep -q "Rebuilding" ${test_log}; then
        Error "Expect kdumpctl restart succeed without rebuliding kdump img. But it didn't. Please check ${test_log}."
    else
        Log "Test Pass"
    fi
    Report "${test_name}"

    Log "Restore kdump and /boot RW mount"
    cp -r kdump_config_bk "${KDUMP_CONFIG}"
    if [ "$boot_permission" != 'ro' ]; then
        mount -o remount,rw /boot || Error "Failed to remount /boot as rw"
    fi
    RestartKdump

    ((error+=${test_result}))
}

# --- start ---
Multihost SystemCrashTest TriggerSysrqC RegressionTest
