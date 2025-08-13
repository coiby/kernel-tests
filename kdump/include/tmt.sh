#!/bin/bash
# Copyright (c) 2025 Red Hat, Inc. All rights reserved.
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

assign_server_roles() {
    if [ -n "${TMT_TOPOLOGY_BASH}" ] && [ -f "${TMT_TOPOLOGY_BASH}" ]; then
        # assign roles based on tmt topology data
        # shellcheck source=/dev/null
        . "${TMT_TOPOLOGY_BASH}"

        if [[ $(grep -Ec "TMT_GUESTS\[.*role\]" "${TMT_TOPOLOGY_BASH}") -gt 1 ]]; then
            export SERVERS=${TMT_GUESTS[server.hostname]}
            export CLIENTS=${TMT_GUESTS[client.hostname]}
        fi

        export HOSTNAME=${TMT_GUEST[hostname]}
    fi
}

assign_server_roles
