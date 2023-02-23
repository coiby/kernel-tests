#!/bin/bash
#
# Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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
    cki_run "$STQE_TEST_EXE run -t iscsi/iscsi_params.py"
    typeset -i rc=$?
    (( rc != 0 )) && return $CKI_FAIL || return $CKI_PASS
}

# stqe_init will abort the task if fails to run
stqe_init

runtest
rc=$?

exit $rc
