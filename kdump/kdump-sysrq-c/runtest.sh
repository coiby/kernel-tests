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

        # Restore kdump configurations and clear previous vmcores if any
        Cleanup

        # Remove -s from KEXEC_ARGS if it presents in default options.
        # Kdump would then load/unload crash kernel by kexec_load instead
        # of kexec_file_load(). kexec_load() will not verify kernel key
        # This is to make both kexec_load() and kexec_file_load() are tested
        # no matter what default option is.
        AppendSysconfig KEXEC_ARGS remove "-s"
        RestartKdump

        ReportSystemInfo

        TriggerSysrqPanic
        rm -f "${C_REBOOT}"
    else
        rm -f "${C_REBOOT}"
        GetCorePath || return

        if [ "${ANALYZE_VMCORE,,}" != "true" ]; then
          return
        fi

        # Analyse the vmcore by crash utilities
        PrepareCrash
        [ $? -eq 1 ] && return

        # Only check the return code of this session.
        cat <<EOF > "${K_TESTAREA}/crash-simple.cmd"
bt -a
ps
log
exit
EOF
        local vmcores
        CheckVmlinux

        Log "- Analyze the vmcore by crash utilities."
        if [ "${K_KVARI}" = 'rt' ]; then
            CrashCommand "--reloc=12m" "${vmlinux}" "${vmcore}"
        else
            CrashCommand "" "${vmlinux}" "${vmcore}"
        fi
    fi
}

RunTest Crash
