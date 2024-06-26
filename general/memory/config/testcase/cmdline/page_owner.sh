#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: page_owner sanity check
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


function read_page_owner()
{
    local result_file="/sys/kernel/debug/page_owner"
    rlRun "tail -n 200 $result_file | tee page_owner"
    rlRun "grep \"Page allocated via order\" page_owner" 0
    rlRun "grep -E 'PFN (0x)?[[:xdigit:]]* .*Block [0-9]* type .* Flags' page_owner" 0
    rlRun "grep -E '[[:alpha:][:alnum:]_]+\+0x[[:alnum:]]+' page_owner" 0
}

function page_owner()
{
    if ! grep CONFIG_PAGE_OWNER=y /boot/config-$(uname -r); then
        rlLog "page_owner is not supported in this kernel, please check kernel config. skip."
        return 0
    fi

    setup_cmdline_args "page_owner=on" PAGE_OWNER && read_page_owner
    cleanup_cmdline_args "page_owner=on"
    test -f page_owner && rm -f page_owner

    return 0
}
