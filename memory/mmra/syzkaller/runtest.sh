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
. ../../../kernel-include/runtest.sh

local_dir=${local_dir:-"/root/tmp"}
timer=${timer:-3600} # In seconds. Defaults to 1 hour.
verbose=${verbose:-""}
# If setting mm_syscalls to leave a trailing comma ,.
#
if [ "$(arch)" = "x86_64" ]; then
    mm_syscalls=${mm_syscalls:-'"mmap", "mprotect", "munmap", "brk", "mremap", "msync", "mincore", "madvise", "mlock", "munlock", "mlockall", "munlockall", "mbind", "membarrier", "mlock2", "shmget", "shmat", "shmctl", "shmdt", "set_mempolicy", "get_mempolicy", "pkey_mprotect", "pkey_alloc", "pkey_free", "process_vm_readv", "process_vm_writev",'}
else
    mm_syscalls=${mm_syscalls:-'"mmap", "mprotect", "munmap", "brk", "mremap", "msync", "mincore", "madvise", "mlock", "munlock", "mlockall", "munlockall", "mbind", "membarrier", "mlock2", "shmget", "shmat", "shmctl", "shmdt", "set_mempolicy", "get_mempolicy", "process_vm_readv", "process_vm_writev",'}
fi
# shellcheck disable=SC2016
supportcalls=${suportcalls:-'"clone3", "geteuid", "getresuid", "getegid", "getgid", "getgroups", "getresgid", "getpgid", "getpid", "newfstatat", "memfd_create", "memfd_secret", "mq_open", "io_uring_setup", "perf_event_open", "openat$cgroup", "openat$cgroup_root", "openat$binderfs", "socket$xdp", "syz_open_dev$usbfs", "syz_open_dev$usbmon"'}

create-test-cfg()
{
    local vm_param
    local targets=$(echo "$1" | awk -F' ' '{for(i=1;i<=NF;i++){printf "\"%s\", ", $i}}' | sed 's/, $//')
    local syscalls="${mm_syscalls} ${supportcalls}"
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
    "enable_syscalls" : [
    ${syscalls}
    ],
    "no_mutate_syscalls" : [
    ${supportcalls}
    ],
    "syzkaller": "/root/syzkaller/",
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
        rlRun "pushd /root"
        rlRun "git clone https://github.com/google/syzkaller"
        rlRun "pushd syzkaller"
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
        rlWatchdog "/root/syzkaller/bin/syz-manager ${verbose} -config /root/syzkaller/syzkaller-test.cfg" "${timer}"
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
        rlRun "/root/syzkaller/bin/syz-db unpack ${local_dir}/syz-manager-logs/corpus.db ${local_dir}/corpus_dir"
        for call in ${mm_syscalls}; do
            syscall=$(echo "${call//\"}" | sed -e 's/,//')
            if grep -q "^${syscall}[$,(]" "${local_dir}"/corpus_dir/* ; then
                rlPass "${syscall} executed."
            else
               rlFail "${syscall} not executed."
            fi
        done
        rlRun "dmesg > dmesg-mmsyscalls.log"
        rlFileSubmit dmesg-mmsyscalls.log
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "tar cf syzkaller_test_results.tar ${local_dir}"
        rlFileSubmit syzkaller_test_results.tar
        rlRun "rm -rf /root/syzkaller"
        rlRun "rm -rf /root/go"
        rlRun "rm -rf ${local_dir}" 0,1
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
