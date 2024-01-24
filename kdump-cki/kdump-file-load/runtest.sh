#!/bin/bash
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


# Source kdump common functions
. ../../cki_lib/libcki.sh || exit 1
. ../include/runtest.sh

TEST="/kdump/crash-sysrq-c"

ANALYZE_VMCORE="${ANALYZE_VMCORE:-true}"

Crash()
{
    if [ ! -f "${C_REBOOT}" ]; then
        SetupKdump
        Cleanup

        # This tests kdump kernel to be loaded with *kexec_file_load* explicitly
        # no matter what default option is for kexec
        # kexec_file_load() verifies kernel key if it's in lockdown or key forcing mode
        AppendSysconfig KEXEC_ARGS remove "-c"
        AppendSysconfig KEXEC_ARGS add "-s"

        # Add 'KDUMP_STDLOGLVL=4' to /etc/sysconfig/kdump for getting more debug messages which is
        # useful for analyzing kdump failure
        Log "- Add 'KDUMP_STDLOGLVL=4' in '${KDUMP_SYS_CONFIG}'"
        sed -i "/^KDUMP_STDLOGLVL=/d" ${KDUMP_SYS_CONFIG}
        echo "KDUMP_STDLOGLVL=4" >> ${KDUMP_SYS_CONFIG}

        # This is for debugging purpose in case kdump kernel got OOM on Fedora
        if $IS_FC; then
            AppendSysconfig KDUMP_COMMANDLINE_APPEND add "rd.memdebug=1"
        fi

        RestartKdump
        TriggerSysrqPanic
        rm -f "${C_REBOOT}"
    else
        rm -f "${C_REBOOT}"

        local log_files="vmcore-dmesg.txt"

        # kexec-dmesg.log is added in RHEL-8.4 (BZ1817042).
        if ! $IS_RHEL || (( $(bc <<< "${RELEASE}.${RELEASE_MINOR}>8.3") )); then
            log_files+=" kexec-dmesg.log"
        fi

        # Get the file path and upload it.
        for f in ${log_files}; do
            # shellcheck disable=SC2154
            GetDumpFile "${f}" && RstrntSubmit "${dump_file_path}"
        done

        GetCorePath || return

        # Analyse the vmcore by crash utilities if ANALYZE_VMCORE=true
        [ "${ANALYZE_VMCORE,,}" == "true" ] && {
            PrepareCrash && SimpleCrashAnalyseTest
        }
    fi
}

RunTest Crash
