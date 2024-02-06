#!/bin/bash
# Copyright (c) 2022 Red Hat, Inc. All rights reserved. This copyrighted
# material is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
# USA.
#
# Author: Filip Suba <fsuba@redhat.com>

source ../../include/libstqe.sh

function runtest()
{
    #echo "$ENV_PARAMS";
    export STRATIS_DBUS_TIMEOUT=500000
    #stqe-test run --fmf --filter component:stratis "$ENV_PARAMS"
    stqe-test run --fmf -f component:stratis --filter tags:multiple_device --filter tier:1 --setup free_disks
    for key in $(stratis --propagate key list | grep -v 'Key Description');do
        stratis --propagate key unset "$key"
    done
    # stratis report after testing
    stratis --propagate report engine_state_report
}

# stqe_init will abort the task if fails to run
stqe_init

runtest
rc=$?

exit $rc
