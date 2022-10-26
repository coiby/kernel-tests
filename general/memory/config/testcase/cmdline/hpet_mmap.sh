#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Author: Li Wang <liwang@redhat.com>
# Reproducer for bz1660800

function hpet_mmap()
{
    uname -r | grep -q x86_64 || return

    setup_cmdline_args "hpet_mmap=1" HPET_ONE && { rlAssertGrep "hpet_mmap=1" /proc/cmdline; rlRun "journalctl -kb | grep -i 'HPET MMAP enabled'"; }
    setup_cmdline_args "hpet_mmap=0" HPET_ZERO && { rlAssertGrep "hpet_mmap=0" /proc/cmdline; rlRun "journalctl -kb | grep -i 'HPET MMAP disabled'"; }

    cleanup_cmdline_args "hpet_mmap"
}
