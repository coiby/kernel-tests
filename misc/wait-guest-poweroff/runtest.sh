#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/misc/wait-guest-poweroff
#   Description: Wait for guest poweroff
#   Author: Erico Nunes <ernunes@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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

# Enable TMT testing for RHIVOS
. ../../cki_lib/libcki.sh || exit 1

if ! cki_is_kernel_automotive; then
    # Include rhts environment
    . /usr/bin/rhts-environment.sh
fi

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

WAIT_STATE=${WAIT_STATE:-"shut off"}

# - use remote URI if running on remote node else just run locally as usual.
if [ ! -z $RECIPE_ROLE_NODE ]; then
    if [ $RECIPE_ROLE_NODE != $HOSTNAME ];then
        export VIRSH_DEFAULT_CONNECT_URI=${VIRSH_DEFAULT_CONNECT_URI:-qemu+ssh://root@${RECIPE_ROLE_NODE}/system}
    fi
fi

poll_seconds=10

# shellcheck disable=SC2034
get_guest_info.py | while IFS=$'\t' read guest_recipeid guest_name \
    guest_mac guest_loc guest_ks guest_args guest_kernel_options
do
    if [ -z $guest_name ]; then
        echo "No guestname can be found"
        report_result ${TEST}_noguestname FAIL 1
        continue
    fi
    echo "guest name is : $guest_name "

    while true
    do
        if ! virsh domstate $guest_name | head -n1 | grep -q "$WAIT_STATE"
        then
    	    echo "$guest_name still not '$WAIT_STATE', retrying in $poll_seconds seconds."
    	    sleep $poll_seconds
    	    continue
        fi

        echo "$guest_name stopped."
        sleep 60
        break
    done
done

report_result ${TEST}_stopped PASS 0

exit 0
