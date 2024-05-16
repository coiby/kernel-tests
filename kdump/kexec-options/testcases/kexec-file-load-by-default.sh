#!/bin/sh
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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

# Source Kdump tests common functions.
. ../include/runtest.sh

# --- start ---

KexecTest(){
    # kdump is configured with KEXEC_ARGS="-s" by default on RHEL-9 and RHEL-8(except ppc64le machine),kexec_file_load() is used on these architectures.
    if [ $RELEASE -lt 8 ]; then
        Skip "KEXEC_ARGS='-s' is not fully supported."
        return
    elif $IS_RHEL8 && [ "$(uname -m)" = "ppc64le" ]; then
        Skip "On RHEL8,kdump sysconfig option did not use kexec_file_load by default on ppc64le."
        return
    fi

    if [ "$(uname -m)" = "x86_64" ]; then
        CheckSkipTest kexec-tools 2.0.20-34 && return
    elif [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "s390x" ]; then
        CheckSkipTest kexec-tools 2.0.20-46 && return
    fi

    # 1) Check configuration in kdump sysconfig
    RhtsSubmit "${KDUMP_SYS_CONFIG}"
    if grep 'KEXEC_ARGS' "${KDUMP_SYS_CONFIG}" | grep -q '\-s'; then
        Log "kdump is configured with KEXEC_ARGS=\"-s\" by default."
    else
        Error "kdump is not configured with KEXEC_ARGS=\"-s\" by default."
        return
    fi

    # 2) Check trace call when calling kexec load

    # 'kexec -l' or 'kexec -c' can only be run on a system supporting PSCI
    # Warn and stop the test if it doesn't support PSCI
    # https://bugzilla.redhat.com/show_bug.cgi?id=1528933#c2
    if [ "$(uname -m)" = "aarch64" ];then
        LogRun "journalctl -k | grep -i psci | grep -i 'is not implemented'"
        if [ $? -eq 0 ];then
            Warn "This aarch64 system doesn't support PSCI. Terminate the test."
            return
        fi
    fi

    local kexec_file="kexec_file_load.log"
    local kexec_load="kexec_load.log"
    local kdump_file="kdump_file_load.log"
    local kdump_load="kdump_load.log"

    local func_kexec_file="kexec_file_load"
    local func_kexec_load="kexec_load"
    local func_kdump_file="KEXEC_FILE_ON_CRASH"
    local func_kdump_load="KEXEC_ON_CRASH"
    local kernel_options="$(cat /proc/cmdline)"

    local cmd_load="strace kexec -l ${VMLINUZ_PATH} --initrd=${INITRD_IMG_PATH} --command-line=\"${kernel_options}\" -d"
    local cmd_panic="strace kexec -p ${VMLINUZ_PATH}  --initrd=${INITRD_IMG_PATH} --command-line=\"${kernel_options}\" -d"

    rpm -q --quiet strace || InstallPackages strace

    # Make sure to unload kexec after each kexec -l test.
    # And reloading kdump service at the end so it won't break kdump

    # Expect kexec_file_load() to be called for kexec/kdump with "-s"
    LogRun "$cmd_load -s > ${kexec_file} 2>&1"
    CheckKexecResult "${kexec_file}" "$func_kexec_file"
    LogRun "kexec -s -u 2>&1"

    LogRun "$cmd_panic -s > ${kdump_file} 2>&1"
    CheckKexecResult "${kdump_file}" "$func_kdump_file"
    LogRun "kexec -s -p -u"

    # 'kexec -c' - tested on RHEL8 and RHEL9
    #  For RHEL9,it is deprecated since RHEL-9.2(bz2113873#2)
    #  RHEL-7 does not support '-c' option
    if $IS_RHEL8 || $IS_RHEL9; then
        # Expect kexec_load() to be called for kexec/kdump without "-s"
        LogRun "$cmd_load -c > ${kexec_load} 2>&1"
        CheckKexecResult "${kexec_load}" "$func_kexec_load"
        LogRun "kexec -c -u"

        LogRun "$cmd_panic -c > ${kdump_load} 2>&1"
        CheckKexecResult "${kdump_load}" "$func_kdump_load"
        LogRun "kexec -c -p -u"
    fi

    LogRun "kdumpctl reload"
}

CheckKexecResult(){
    local log_file="$1"
    local func="$2"

    RhtsSubmit "$log_file"
    if ! grep -q 'exited with 0' "${log_file}" || ! grep -q "$func" "${log_file}"; then
        Error "Expect $func to be called in kexec load command. But it didn't or command failed to run. Please check $log_file"
    fi
}

Multihost KexecTest
