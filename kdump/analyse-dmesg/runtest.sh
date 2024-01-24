#!/bin/sh

# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
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

#  Author: Guangze Bai <gbai@redhat.com>
#  Update: Ruowen Qin  <ruqin@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

ValidateVmcoreDmesg(){
    # Nothing Placeholder for validating vmcore-dmesg.txt file
    true
}

ValidateKexecDmesg(){
    local file_path="${1}"

    Log "Search patterns for potential errors."

    # Bug 2024011 - swapper/0: page allocation failures seen during intentional crashdump test
    # Fixed in 8.6 kernel-4.18.0-367.el8
    echo '- page allocation failure'

    Log "ERROR MESSAGES BEGIN"
    grep -iw -e 'page allocation failure' \
            ${file_path} 2>&1 | tee -a "${OUTPUTFILE}"
    local errorFound=${PIPESTATUS[0]}
    Log "ERROR MESSAGES END"

    if [ "${errorFound}" -eq 0 ]; then
        Error "Kexec-dmesg.log reported potential errors.Please check kexec-dmesg.log or console.log"
    fi
}

VerifyPermssion(){
    # Bug 1937612: Fixed dmesg permission in RHEL-8.5 kexec-tools 2.0.20-47
    CheckSkipTest kexec-tools 2.0.20-47 && return

    # Skip verifying access permission for remote dump if it's in the single host mode.
    # Because the file permission on a pre-configured vmcore server is unreliable.
    # It can be changed by server admin.
    if grep -v "^#" ${KDUMP_CONFIG} | grep -q -E "^nfs|^ssh|^dracut_args\s+--mount" && \
        [ -z "${CLIENTS}" ]; then
        Log "Skip as it's network dump running in single host mode."
        return
    fi

    local file_path=${1}
    local exp_perm=${2:-600}

    local act_perm=$(stat -c '%a' "${file_path}")
    if [ "${act_perm}" != "${exp_perm}" ]; then
        Error "Fail. Access permision is $act_perm. Expect ${exp_perm})"
    else
        Log "Pass. Access permssion is $act_perm"
    fi
}

AnalyseDmesg(){
    local file_name=${1}

    Log "Analyze dmesg file: ${file_name}"

    # kexec-dmesg.log is added in RHEL-8.4 (BZ1817042) kexec-tools-2.0.20-37.el8
    [ "${file_name}" = kexec-dmesg.log ] && CheckSkipTest kexec-tools 2.0.20-37 && return

    Log "Locate the file"
    GetDumpFile ${file_name}
    # shellcheck disable=SC2154
    if [ $? -ne 0 ]; then
        Error "Couldn't find the dmesg file. Please check kdump process in console log"
        return
    elif [ ! -s "${dump_file_path}" ]; then
        Error "The dmesg file is empty"
        return
    else
        RhtsSubmit "${dump_file_path}"
    fi

    Log "Verify access permission"
    VerifyPermssion "${dump_file_path}"

    Log "Check file content"
    if [[ "${file_name}" =~ "vmcore-dmesg" ]]; then
        ValidateVmcoreDmesg "${dump_file_path}"

    elif [[ "${file_name}" =~ "kexec-dmesg" ]]; then
        ValidateKexecDmesg "${dump_file_path}"
    fi
}

#+---------------------------+

for f in vmcore-dmesg.txt kexec-dmesg.log; do
    MultihostStage "${f}" "AnalyseDmesg" "${f}"
done
