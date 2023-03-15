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

SetRemoteServer NFS || {
    Error "Not find remote server"
    Report
}

CopyVmcore()
{
    if [ ! -f "${K_NFS}" ] || [ ! -f "${K_PATH}" ]; then
        Error "Expect files ${K_NFS} or ${K_PATH}. But not found"
        return
    fi

    EXPORT="$(cat "${K_NFS}")"
    DUMP_PATH="$(cat "${K_PATH}")"

    Log "-------------------------------------------------"
    Log "The NFS Server: ${NFS_SERVER}"
    Log "The EXPORT: ${EXPORT}"
    Log "The Dump PATH: ${DUMP_PATH}"
    Log "-------------------------------------------------"

    if [ -z "${NFS_SERVER}" ] || [ -z "${EXPORT}" ] || [ -z "${DUMP_PATH}" ]; then
        Error "Failed to find NFS dump path where vmcore is saved to"
        return
    fi

    Log "Copy vmcore from NFS server to client"
    # Copy files to same path as the export path on the server.
    mkdir -p "${EXPORT}/${DUMP_PATH}"
    mkdir -p "${TESTAREA}/tempnfs"

    LogRun "mount \"${NFS_SERVER}:${EXPORT}\" \"${TESTAREA}/tempnfs\""
    LogRun "cp -r -f \"${TESTAREA}/tempnfs/${DUMP_PATH}\"/* \"${EXPORT}/${DUMP_PATH}/\"" ||
        Error "Failed to mount or cp vmcore from NFS server."

    sync
    umount "${TESTAREA}"/tempnfs
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
