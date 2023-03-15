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

# To prepare a SSH server manually, id_rsa.pub must be sent to ~/.ssh/authorized_keys
# on SSH server,

# Accept Parameters:
#   SSH_SERVER - SSH server (hostname or IP)
#   SSH_USER - SSH User used in SSH connection (default is root)

#   DUMP_PATH - Dump root path ${Server}.
#               Default is "/".
#               Vmcore will be dump to /${DUMP_PATH}/${SUBMITTER}/${JOBID}/${HOSTNAME}"

#   IP_TYPE - hostname or v4 or v6. Default to v4

#+---------------------------+
CheckUnexpectedReboot

SetRemoteServer SSH || {
    Error "Not find remote server"
    Report
}

if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
    Log "Run as client"
    TEST="${TEST}/client"

    # Abort entire recipeset if not reciving Done signal from server
    Log "[sync] Blocked till the server side is ready."
    rstrnt-sync-block -s "READY" "${SERVERS}" --timeout 3600 || FatalError "[sync] Not receiving READY signal from server"

    SetupSSHClient

    Log "[sync] Client finished"
    rstrnt-sync-set -s "DONE"

elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
    Log "Run as server"
    TEST="${TEST}/server"

    SetupSSHServer

    Log "[sync] Server is ready"
    rstrnt-sync-set -s "READY"

    # Abort only current task if not receving Done signal from client
    Log "[sync] Blocked till the client side is done."
    rstrnt-sync-block -s "DONE" "${CLIENTS}" --timeout 3600 || MajorError "[sync] Not receiving DONE signal from client"
else
    Log "Run as single host client"
    SetupSSHClient
fi

Report
