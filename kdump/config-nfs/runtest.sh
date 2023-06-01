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

# Accept Parameters:
#   NFS_SERVER - NFS server (hostname or IP)
#   EXPORT - Export path configred on NFS Server.
#            Default "/mnt/testarea/nfs"
#   MNT_PATH - Path where the nfs fs will be mounted on the client.
#              Default "/mnt/testarea/nfs"
#   DUMP_PATH - Dump root path ${Server}. (Relative to) {EXPORT}
#               Default is "/".
#               Vmcore will be dump to {EXPORT}/${DUMP_PATH}/${SUBMITTER}/${JOBID}/${HOSTNAME}"

#   NFS_MOUNT_DRACUT_ARGS - true or false. Whether to specify nfs target in dracut_args instead
#                           of the "nfs <nfs mount>"
#                           Default is "false".

#   FSTAB_ENTRY - true or false. Whether add nfs mount entry to fstab (default is 'false')
#   FSTAB_ENTRY_OPTS - Specify fstab nfs mount entry options in fstab.
#                      Default is "defaults,noauto"

#   TARGET_MOUNTED - true or false. Whether mount the target (default is 'true')
#   TARGET_MOUNTED_OPTS - Specify fstab nfs mount options.
#                         Default is "defaults,noauto"

#+---------------------------+
CheckUnexpectedReboot

SetRemoteServer NFS || {
    Error "Not find remote server"
    Report
}

if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
    Log "Run as client"
    TEST="${TEST}/client"

    # Abort entire recipeset if not reciving Done signal from server
    Log "[sync] Blocked till the server side is ready."
    rstrnt-sync-block -s "READY" "${SERVERS}" --timeout 3600 || FatalError "[sync] Not receiving READY signal from server"

    SetupNFSClient

    Log "[sync] Client finished"
    rstrnt-sync-set -s "DONE"

elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
    Log "Run as server"
    TEST="${TEST}/server"

    SetupNFSServer

    Log "[sync] Server is ready"
    rstrnt-sync-set -s "READY"

    # Abort only current task if not receving Done signal from client
    Log "[sync] Blocked till the client side is done."
    rstrnt-sync-block -s "DONE" "${CLIENTS}" --timeout 3600 || MajorError "[sync] Not receiving DONE signal from client"
else
    Log "Run as single host client"
    SetupNFSClient
fi

Report
