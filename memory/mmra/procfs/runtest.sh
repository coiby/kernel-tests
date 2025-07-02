#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../kernel-include/runtest.sh || exit 1
. ../../../syzkaller/include.sh || exit 1

git_patches="../memory/mmra/procfs/procfs.patch"
SYZKALLER_COMMIT_HASH="21339d7b9986698282dce93709157dc36907fbf8"
# shellcheck disable=SC2016
main_syscalls=${main_syscalls:-'
    "openat$ark",
    "openat$cm",
    "openat$cp",
    "openat$cua",
    "openat$dc",
    "openat$des",
    "openat$et",
    "openat$lm",
    "openat$lrr",
    "openat$lvl",
    "openat$mfek",
    "openat$mfk",
    "openat$mfr",
    "openat$mma",
    "openat$mrb",
    "openat$odt",
    "openat$ok",
    "openat$okat",
    "openat$om",
    "openat$or",
    "openat$pc",
    "openat$plu",
    "openat$poom",
    "openat$pphf",
    "openat$st",
    "openat$statr",
    "openat$swap",
    "openat$urk",
    "openat$vcp",
    "openat$wbf",
    "openat$wsf",
    "write$ark",
    "write$cm",
    "write$cp",
    "write$cua",
    "write$dc",
    "write$des",
    "write$et",
    "write$lm",
    "write$lrr",
    "write$lvl",
    "write$mfek",
    "write$mfk",
    "write$mfr",
    "write$mma",
    "write$mrb",
    "write$odt",
    "write$ok",
    "write$okat",
    "write$om",
    "write$or",
    "write$pc",
    "write$plu",
    "write$poom",
    "write$pphf",
    "write$st",
    "write$statr",
    "write$swap",
    "write$urk",
    "write$vcp",
    "write$wbf",
    "write$wsf"'}

#    "openat$mmc",
#    "write$mmc",
#    "max_map_count",

procfs_entry=${procfs_entry:-'
    "admin_reserve_kbytes",
    "compaction_proactiveness",
    "compact_memory",
    "compact_unevictable_allowed",
    "dirtytime_expire_seconds",
    "drop_caches",
    "extfrag_threshold",
    "laptop_mode",
    "legacy_va_layout",
    "lowmem_reserve_ratio",
    "memory_failure_early_kill",
    "memory_failure_recovery",
    "min_free_kbytes",
    "min_slab_ratio",
    "min_unmapped_ratio",
    "mmap_min_addr",
    "mmap_rnd_bits",
    "numa_zonelist_order",
    "oom_dump_tasks",
    "oom_kill_allocating_task",
    "overcommit_kbytes",
    "overcommit_memory",
    "overcommit_ratio",
    "page-cluster",
    "page_lock_unfairness",
    "panic_on_oom",
    "percpu_pagelist_high_fraction",
    "stat_interval",
    "stat_refresh",
    "swappiness",
    "unprivileged_userfaultfd",
    "user_reserve_kbytes",
    "vfs_cache_pressure",
    "watermark_boost_factor",
    "watermark_scale_factor",
    "zone_reclaim_mode"'}

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        syzkaller_setup
    rlPhaseEnd
    rlPhaseStartTest
        syzkaller_run
        syzkaller_check_results
        rlLog "The following tuneables are covered."
        for call in ${procfs_entry}; do
            entry=$(echo "${call//\"}" | sed -e 's/,//')
            rlLog "${entry}"
        done
        rlRun "dmesg > dmesg-mmsyscalls.log"
        rlFileSubmit dmesg-mmsyscalls.log
    rlPhaseEnd
    rlPhaseStartCleanup
        syzkaller_cleanup
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
