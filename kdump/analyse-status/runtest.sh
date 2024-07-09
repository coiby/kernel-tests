#!/bin/sh

# Copyright (c) 2019 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#  Author: Xiaowu Wu <xiawu@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# In fence kdump it will create 2 cluster nodes. And config and trigger fence kdump in node one.
# Basically two cluster nodes are equal. There is no client/master.

USE_ALIAS=${USE_ALIAS:-"false"}
READ_FROM_PCS=${READ_FROM_PCS:-"true"}

CheckUnexpectedReboot

case "${TESTARGS,,}" in
    fence)
        if [ "${RELEASE}" -lt 7 ]; then
            Skip "Fence kdump test is only applicable to RHEL7 or later releases"
            Report
        elif echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
            Log "- Check cluster node"
            TEST="${TEST}/client"

            Log "- Client ready for server to check fence kdump status."
            rstrnt-sync-set -s "FENCE_DONE"

            Log "- Waiting server to finish fence kdump check"
            rstrnt-sync-block -s "FENCE_CHECK_DONE" "${SERVERS}" --timeout 3600 || MajorError "- Not receiving signal FENCE_CHECK_DONE from server"

        elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
            Log "- Check cluster node"
            TEST="${TEST}/server"

            Log "- Waiting client to be ready for fence kdump status check."
            rstrnt-sync-block -s "FENCE_DONE" "${CLIENTS}" --timeout 3600 || MajorError "- Not receiving signal FENCE_DONE from client"

            # Expect to see "received valid message from xxxx"  in system log
            # A succeed log would be lik:
            # stonith-ng[16041]:  notice: kdump can fence (reboot) node1: none
            # stonith-ng[16041]: warning: Agent 'fence_kdump' does not advertise support for 'reboot', performing 'off' action instead
            # fence_kdump[46914]: waiting for message from '10.16.185.172'
            # fence_kdump[46914]: received valid message from '10.16.185.172'

            # A fail log would be like:
            # fence_kdump[46622]: waiting for message from '10.16.185.172'
            # stonith-ng[16041]: warning: fence_kdump_off_1 process (PID 46622) timed out
            # stonith-ng[16041]: warning: fence_kdump_off_1:46622 - timed out after 60000ms


            if which journalctl; then
                journalctl -b | grep "fence_kdump" | grep -i "received valid message from"
            else
                grep "fence_kdump" /var/log/messages | grep -i "received valid message from"
            fi

            [ $? -ne 0 ] && {
                Error "Not received fence kdump message from ${CLIENTS}"
                if which journalctl; then
                    journalctl -b > "messages.log"
                else
                    cat /var/log/messages > "messages.log"
                fi
                RhtsSubmit "$(pwd)/messages.log"
            }
            Log "- Done checking fence kdump status"
            rstrnt-sync-set -s "FENCE_CHECK_DONE"

        else
            Error "Neither server nor client"
        fi

        Report "$TESTARGS"
        ;;
    *)
        Error "Invalid TESTARGS: $TESTARGS".
    ;;
esac

Report
