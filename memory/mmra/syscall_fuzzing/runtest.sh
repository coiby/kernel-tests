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
. ../../../cmdline_helper/libcmd.sh || exit 1
. ../../../syzkaller/include.sh || exit 1

mm_syscalls_default='
    "brk",
    "cachestat",
    "fadvise64_64",
    "fallocate",
    "madvise",
    "membarrier",
    "memfd_create",
    "memfd_secret",
    "mincore",
    "mlock",
    "mlock2",
    "mlockall",
    "mmap",
    "mprotect",
    "mremap",
    "msync",
    "munlock",
    "munlockall",
    "munmap",
    "process_madvise",
    "process_mrelease",
    "process_vm_readv",
    "process_vm_writev",
    "readahead",
    "remap_file_pages",
    "shmat",
    "shmctl",
    "shmdt",
    "shmget",
    "swapoff",
    "swapon"'

if [ "$(arch)" = "x86_64" ]; then
    mm_syscalls_default='
        "${mm_syscalls_default}",
        "pkey_alloc",
        "pkey_free",
        "pkey_mprotect"'
fi

main_syscalls=${mm_syscalls_default}

# shellcheck disable=SC2016
support_syscalls='
    "clone3",
    "getegid",
    "geteuid",
    "getgid",
    "getgroups",
    "getpgid",
    "getpid",
    "getresgid",
    "getresuid",
    "mq_open",
    "newfstatat",
    "openat$binderfs",
    "openat$cgroup",
    "openat$cgroup_root",
    "openat$pidfd",
    "openat$thread_pidfd",
    "perf_event_open",
    "pidfd_open",
    "syz_open_dev$usbfs",
    "syz_open_dev$usbmon"'

# known unsupported syscalls in mmap
disable_syscalls='
    "mmap$DRM_I915",
    "mmap$DRM_MSM",
    "mmap$KVM_VCPU",
    "mmap$IORING_OFF_CQ_RING",
    "mmap$IORING_OFF_SQ_RING",
    "mmap$IORING_OFF_SQES",
    "mmap$bifrost",
    "mmap$dsp",
    "mmap$fb",
    "mmap$qrtrtun",
    "mmap$snddsp",
    "mmap$snddsp_control",
    "mmap$snddsp_status",
    "mmap$xdp"'

rlJournalStart
    if [ "${REBOOTCOUNT}" -eq 0 ]; then
        rlPhaseStartSetup
            rlShowRunningKernel
            syzkaller_setup
            # needed to test memfd_secret syscall.
            rlRun "change_cmdline 'secretmem.enable=1'" || exit 1
            rlRun "rstrnt-reboot"
        rlPhaseEnd
    fi
    if [ "${REBOOTCOUNT}" -eq 1 ]; then
        rlPhaseStartTest
            syzkaller_run
            syzkaller_check_results
        rlPhaseEnd
        rlPhaseStartCleanup
            syzkaller_cleanup
            # Reset to default cmdline settings.
            rlRun "change_cmdline '-secretmem.enable=1'" || exit 1
            rlRun "rstrnt-reboot"
        rlPhaseEnd
    fi
rlJournalEnd
rlJournalPrintText
