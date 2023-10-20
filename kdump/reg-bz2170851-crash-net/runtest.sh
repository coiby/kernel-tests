#!/bin/bash
# Copyright (c) 2023 Red Hat, Inc. All rights reserved.
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

#  Author: Xiaoying Yan   <yiyan@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

PrepareCrash

# Bug 2170851 - [RFE] Display an IPv6 address of a network interface in the output of the 'net' command.
# Fixed in RHEL-9.3 crash-8.0.3-1.el9

if $IS_RHEL9; then
    CheckSkipTest crash 8.0.3-1 && Report
elif $IS_RHEL8; then
    CheckSkipTest crash 7.3.2-8 && Report
else
    Skip "This was supported since RHEL-9.3 and RHEL-8.9."
    Report
fi

CrashNetCheck() {

    # Get IPv6 address
    Log "Get ipv6 address."
    LogRun "ip ad show | grep 'inet6' |grep '/64' | head -n 2 |awk -F '/' '{print \$1}' |awk '{print \$NF}' > ipv6.txt"
    LogRun "cat ipv6.txt"

    cat <<EOF >"crash.net.cmd"
net
exit
EOF
    crash -i crash.net.cmd > "crash.net.log"
    RhtsSubmit "$(pwd)/crash.net.cmd"
    RhtsSubmit "$(pwd)/crash.net.log"

    # On RHEL9,before fix, net returns only the IPv4 address
    # e.g.
    # crash> net
    #    NET_DEVICE     NAME   IP ADDRESS(ES)
    # ffff98fd01223000  lo     127.0.0.1
    # ffff98fd09f00000  eno49  10.74.128.17
    # crash>

    # After the fix, net print all IPv4 address and IPv6 address
    # e.g.
    # crash> net
    #    NET_DEVICE     NAME   IP ADDRESS(ES)
    # ffff98fd01223000  lo     127.0.0.1
    # ffff98fd09f00000  eno49  10.74.128.17 2620:52:0:4a80:8edc:d4ff:feb4:ce4c, fe80::8edc:d4ff:feb4:ce4c
    #  crash>

    while read line
    do
        if [ -z "$(grep $line "$(pwd)/crash.net.log")" ]; then
            Error "The crash command 'net' didn't print IPv6 address $line."
        fi
    done < "ipv6.txt"

    rm -f "crash.net.cmd"
    rm -f "crash.net.log"
}

#-------- Start Test --------
Multihost CrashNetCheck
