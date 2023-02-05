#!/bin/sh

# Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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


ConfigFcoe() {

    #  Install package fcoe-utils package.
    #  And start and enable fcoe and lldpad service.
    rpm -q fcoe-utils || InstallPackages fcoe-utils
    systemctl enable fcoe; systemctl restart fcoe
    systemctl enable lldpad; systemctl restart lldpad

    # Find FCoE devices
    fipvlan -a -c -s
    fcoeadm -i
    if [ ! -f "/etc/multipath.conf" ]; then
        local multi_conf_path=$(find /usr/share/doc/ -name "multipath.conf")
        [ -z "$multi_conf_path" ] && MajorError "- Failed to find multipath.conf template"
        cp -f "$multi_conf_path" "/etc/multipath.conf"
    fi
    systemctl start multipathd;  systemctl enable multipathd
    multipath -l | tee multipath_list.out
    local lun_id
    lun_id=$(cat multipath_list.out | grep -m 1 LUN | awk '{print $1}')
    [ -z "${lun_id}" ] && MajorError "- Failed to find lun by multipath command"
}

# --- start ---
Multihost "ConfigFcoe"

