#!/bin/bash
#
# Copyright (c) 2021 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

source ../../include/libstqe.sh

function runtest
{
    typeset -i rc=0
    typeset tc_list=""
    tc_list+=" lvm/device_mapper_persistent_data/thin"
    tc_list+=" lvm/device_mapper_persistent_data/cache"
    typeset tc=""
    for tc in $tc_list; do
        cki_run "$STQE_TEST_EXE run --fmf --path $tc"
        (( rc += $? ))
    done
    (( rc != 0 )) && return $CKI_FAIL || return $CKI_PASS
}

# stqe_init will abort the task if fails to run
stqe_init

runtest
rc=$?

exit $rc
