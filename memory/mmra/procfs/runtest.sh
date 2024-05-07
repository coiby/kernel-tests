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

local_dir=${local_dir:-"/root/tmp"}
timer=${timer:-3600} # In seconds. Defaults to 1 hour.
verbose=${verbose:-""}
supportcalls=${supportcalls:-""}
discalls=${discalls:-""}
commit=${commit:-"21339d7b9986698282dce93709157dc36907fbf8"}
# shellcheck disable=SC2016
syscalls=${syscalls:-'
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
    "openat$ms_ratio",
    "openat$mur",
    "openat$nzo",
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
    "openat$uu",
    "openat$vcp",
    "openat$wbf",
    "openat$wsf",
    "openat$zrm",
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
    "write$ms_ratio",
    "write$mur",
    "write$nzo",
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
    "write$uu",
    "write$vcp",
    "write$wbf",
    "write$wsf",
    "write$zrm"'}

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

create-test-cfg()
{
    local vm_param
    local targets=$(echo "$1" | awk -F' ' '{for(i=1;i<=NF;i++){printf "\"%s\", ", $i}}' | sed 's/, $//')
    if [[ -n ${supportcalls} ]]; then
        local syscalls="${syscalls}, ${supportcalls}"
    fi
    arch=$(uname -m|sed 's/x86_/amd/g'|sed 's/aarch/arm/g')
    vm_param="\"targets\" : [ ${targets} ], \"target_dir\" : \"${local_dir}/syzkaller-client\""
    cat > syzkaller-test.cfg << EOF
{
    "http": "0.0.0.0:56741",
    "rpc": "127.0.0.1:0",
    "procs" : 1,
    "max_crash_logs" : 10,
    "workdir": "${local_dir}/syz-manager-logs",
    "target": "linux/${arch}",
    "enable_syscalls" : [${syscalls}],
    "disable_syscalls" : [${discalls}],
    "no_mutate_syscalls" : [${supportcalls}],
    "syzkaller": "${syzkaller_root}",
    "sandbox": "none",
    "cover": false,
    "reproduce": false,
    "type": "isolated",
    "vm": {
        ${vm_param}
    }
}
EOF
    [ -e syzkaller-test.cfg ] && return 0 || return 1
}

pkg_mgr=$(K_GetPkgMgr)
rlLog "pkg_mgr = ${pkg_mgr}"
if [[ $pkg_mgr == "rpm-ostree" ]]; then
    export pkg_mgr_inst_string="-A -y --idempotent --allow-inactive install"
    export pkg_mgr_rmv_string="-y --idempotent --allow-inactive uninstall"
else
    export pkg_mgr_inst_string="-y install"
    export pkg_mgr_rmv_string="-y remove"
fi

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        # glibc-static causes an error in syzkaller build
        # /usr/bin/ld: read-only segment has dynamic relocations
        # shellcheck disable=SC2086
        rlRun "${pkg_mgr} ${pkg_mgr_rmv_string} glibc-static"
        rlRun "git clone https://github.com/google/syzkaller"
        rlRun "pushd syzkaller"
        syzkaller_root=$(pwd)
        rlRun "git branch mmra_temp ${commit}"
        rlRun "git switch mmra_temp"
        rlRun "git apply ../procfs.patch"
        rlRun "make"
        sut_ip=$(nmcli | grep -A1 "ip4 default" | grep -v "ip4 default" | awk '{print $2}' | awk -F "/" '{print $1}')
        # create config file:
        rlRun "create-test-cfg ${sut_ip}"
        rlFileSubmit syzkaller-test.cfg
        rlRun "popd"
        rlRun "ssh-keygen -q -t ed25519 -N '' <<< $'\ny' > /dev/null 2>&1"
        rlRun "cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys"
    rlPhaseEnd
    rlPhaseStartTest
        rlRun "dmesg -C"
        start_time=$(date +%s)
        rlWatchdog "${syzkaller_root}/bin/syz-manager ${verbose} -config ${syzkaller_root}/syzkaller-test.cfg" "${timer}"
        end_time=$(date +%s)
        duration=$((${end_time}-${start_time}))
        rlLog "Test duration was ${duration} seconds."
        if [ "${duration}" -lt "${timer}" ]; then
            rlFail "Command ended before timer expired."
        fi
        if [ "$(ls -l "${local_dir}"/syz-manager-logs/crashes)" != "total 0" ]; then
            rlFail "Crash results found."
        else
            rlPass "No crash results found."
        fi
        # Additional verification that all syscalls were executed.
        rlRun "mkdir ${local_dir}/corpus_dir"
        rlRun "${syzkaller_root}/bin/syz-db unpack ${local_dir}/syz-manager-logs/corpus.db ${local_dir}/corpus_dir"
        for call in ${syscalls}; do
            syscall=$(echo "${call//\"}" | sed -e 's/,//')
            if grep -q "^${syscall}[$,(]" "${local_dir}"/corpus_dir/* ; then
                rlPass "${syscall} executed."
            else
               rlFail "${syscall} not executed."
            fi
        done
        rlLog "The following /proc/sys/vm tuneables are covered."
        for call in ${procfs_entry}; do
            entry=$(echo "${call//\"}" | sed -e 's/,//')
            rlLog "${entry}"
        done
        rlRun "dmesg > dmesg-mmsyscalls.log"
        rlFileSubmit dmesg-mmsyscalls.log
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "tar cf syzkaller_test_results.tar ${local_dir}"
        rlFileSubmit syzkaller_test_results.tar
        rlRun "rm -rf /root/go"
        rlRun "rm -rf ${local_dir}" 0,1
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
