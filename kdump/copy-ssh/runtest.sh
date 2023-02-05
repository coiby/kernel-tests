#!/bin/sh

# Copyright (C) 2008 CAI Qian <caiqian@redhat.com>
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

#+---------------------------+
CheckUnexpectedReboot

SetRemoteServer SSH || {
    Error "Not find remote server"
    Report
}

CopyVmcore()
{
    [ -f "${K_PATH}" ] && DUMP_PATH="$(cat "${K_PATH}")"
    if [ -z "${DUMP_PATH}" ]; then
        Error "Failed to find SSH dump path where vmcore is saved to"
        return
    fi

    Log "List files under the dump path on the SSH server."
    LogRun "ssh -o StrictHostKeyChecking=no -i \"${K_ID_RSA}\" \"${SSH_USER}@${SSH_SERVER}\" \"ls -tl ${DUMP_PATH}/*/vmcore*\""

    # # 'makedumpfile' would create vmcore.flat on SSH server
    # # Also, it may also generate vmcore-incomplete.
    # files=$(ssh -i "${K_ID_RSA}" "${SSH_USER}@{SSH_SERVER}" "ls ${DUMP_PATH}/*/vmcore*" 2>/dev/null)

    # for f in $files; do
    #     [[ $f == */vmcore || $f == */vmcore.flat ]] && vmcore="$f"
    #     [[ $f == */vmcore-dmesg.txt ]] && dmesg="$f"
    # done

    Log "Copy vmcore from SSH server to client"
    # Copy files to same path as the path on the server.
    mkdir -p "${DUMP_PATH}"
    LogRun "scp -r -o StrictHostKeyChecking=no -i \"${K_ID_RSA}\" \"${SSH_USER}@${SSH_SERVER}:${DUMP_PATH}/*\" \"${DUMP_PATH}/\""
    [ $? -ne 0 ] && {
        Error "No vmcore copied from SSH server"
        return
    }

    local flat_file_path=$(find "${DUMP_PATH}" -name "vmcore.flat")
    if [ -f "${flat_file_path}" ]; then
        Log "Convert vmcore.flat to vmcore"
        LogRun "cat \"${flat_file_path}\" | makedumpfile -R \"${flat_file_path%.flat}\""
    fi
}


if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
    Log "Run as client"
    TEST="${TEST}/client"

    # Abort entire recipeset if not reciving READY signal from server.
    Log "[sync] Blocked till the server side is ready."
    rstrnt-sync-block -s "READY" "${SERVERS}" --timeout 3600 || FatalError "[sync] Not receiving READY signal from server"

    CopyVmcore

    Log "- Client finished."
    rstrnt-sync-set -s "DONE"

elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
    Log "Run as server"
    TEST="${TEST}/server"

    Log "[sync] Server finished."
    rstrnt-sync-set -s "READY"
    rstrnt-sync-block -s "DONE" "${CLIENTS}" --timeout 3600 || MajorError "[sync] Not receiving DONE signal from client"

else
    Log "Run as single host client"
    CopyVmcore
fi

Report
