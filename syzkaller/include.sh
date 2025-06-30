#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
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

# Include beakerlib environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")

. ${CDIR}/../kernel-include/runtest.sh

# Source guest topology stored in TMT_TOPOLOGY_BASH
# shellcheck disable=SC1090
. "$TMT_TOPOLOGY_BASH"

GO_VERSION=${GO_VERSION:-"1.24.4"}
SYZKALLER_COMMIT_HASH=${SYZKALLER_COMMIT_HASH:-"5d7e17caf7d0971d22446d8a81bcf1cd8c18a0dc"} # 2025-06-10
SSH_OPTIONS=${SSH_OPTIONS:-"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"}

# Check if DUT_HOSTNAME is set, otherwise use TMT_GUESTS["client.hostname"]
# If neither is set, default to single host test
if [[ -n "${DUT_HOSTNAME}" ]]; then
    DUT="${DUT_HOSTNAME}"
elif [[ -n "${TMT_GUESTS["client.hostname"]}" ]]; then
    DUT="${TMT_GUESTS["client.hostname"]}"
else
    DUT="127.0.0.1"
fi

verbose=${verbose:-""}

git_patches=${git_patches:-""}

# syscalls to fuzz
main_syscalls=${main_syscalls:-''}

# known unsupported syscalls
disable_syscalls=${disable_syscalls:-'"mmap$DRM_I915",
    "mmap$DRM_MSM",
    "mmap$KVM_VCPU",
    "mmap$bifrost",
    "mmap$dsp",
    "mmap$fb",
    "mmap$qrtrtun",
    "mmap$snddsp",
    "mmap$snddsp_control",
    "mmap$snddsp_status"'}

# shellcheck disable=SC2016
support_syscalls=${support_syscalls:-''}

time=${time:-3600}

arch=$(uname -m|sed 's/x86_/amd/g'|sed 's/aarch/arm/g')


function create_syzkaller_config() {
    local syscalls="${main_syscalls}${support_syscalls:+, ${support_syscalls}}"
    cat <<EOF > syzkaller.conf
{
    "http": "127.0.0.1:56741",
    "rpc": "127.0.0.1:0",
    "max_crash_logs" : 10,
    "target": "linux/${arch}",
    "syzkaller": "${syzkaller_root}",
    "sshkey": "/root/.ssh/id_ed25519",
    "cover": false,
    "type": "isolated",
    "reproduce": false,
    "workdir": "${syzkaller_workdir}",
    "vm": {
        "targets": ["$DUT"],
        "target_dir": "/root/tmp/syzkaller"
    },
    "enable_syscalls": [${syscalls}],
    "disable_syscalls": [${disable_syscalls}],
    "no_mutate_syscalls": [${support_syscalls}]
}
EOF
    [ -e syzkaller.conf ] && return 0 || return 1
}

function syzkaller_setup() {
    rlLog "DUT is $DUT"
    if ! ping -c 1 $DUT > /dev/null 2>&1; then
        rlFail "DUT is not reachable. Please check the network connection."
        exit 1
    fi

    # Install ssh keys to DUT
    rlRun "ssh-keygen -q -t ed25519 -N '' <<< $'\ny' > /dev/null 2>&1"
    if [ "$DUT" = "127.0.0.1" ]; then
        rlRun "cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys"
    else
        rlRun "ssh-keyscan $DUT 2>/dev/null >> ~/.ssh/known_hosts"
        rlRun "sshpass -p password ssh-copy-id root@$DUT"
        # Log DUT kernel version
        dut_kernel_version=$(ssh $SSH_OPTIONS root@$DUT uname -r)
        rlLog "DUT kernel version: ${dut_kernel_version}"
        # Clear dmesg on DUT
        rlRun "ssh $SSH_OPTIONS root@$DUT 'dmesg -c'"
    fi

    # Remove glibc-static from server
    pkg_mgr=$(K_GetPkgMgr)
    if [[ $pkg_mgr == "rpm-ostree" ]]; then
        export pkg_mgr_rmv_string="-y --idempotent --allow-inactive uninstall"
    else
        export pkg_mgr_rmv_string="-y remove"
    fi
    rlRun "${pkg_mgr} ${pkg_mgr_rmv_string} glibc-static"

    # Install Go
    rlRun "rm -rf /root/go${GO_VERSION}"
    rlRun "mkdir -p /root/go${GO_VERSION}"
    rlRun "wget -q https://go.dev/dl/go${GO_VERSION}.linux-arm64.tar.gz"
    rlRun "tar -C /root/go${GO_VERSION} -xzf go${GO_VERSION}.linux-arm64.tar.gz"
    export PATH="/root/go${GO_VERSION}/go/bin:$PATH"

    # Build Syzkaller
    rlRun "rm -rf /root/tmp/syzkaller_root"
    rlRun "mkdir -p /root/tmp/syzkaller_root"
    cd /root/tmp/syzkaller_root
    rlRun "git_retry_clone https://github.com/google/syzkaller"
    cd syzkaller
    rlRun "git checkout ${SYZKALLER_COMMIT_HASH}"
    syzkaller_root=$(pwd)
    syzkaller_workdir=${syzkaller_root}/workdir
    for git_patch in $git_patches; do
        rlRun "git apply ${CDIR}/$git_patch"
    done
    rlRun make

    # Create config
    rlRun create_syzkaller_config
    rlFileSubmit syzkaller.conf
}

function syzkaller_run() {
    # Run syzkaller
    start_time=$(date +%s)
    rlWatchdog "${syzkaller_root}/bin/syz-manager ${verbose} -config ${syzkaller_root}/syzkaller.conf" "${time}"
    end_time=$(date +%s)
}

function syzkaller_start() {
    # Run syzkaller in the background
    start_time=$(date +%s)
    rlRun "tmux new-session -d -s syzkaller '${syzkaller_root}/bin/syz-manager ${verbose} -config ${syzkaller_root}/syzkaller.conf'"
    echo $syzkaller_root > /var/tmp/syzkaller.root
    echo $start_time > /var/tmp/syzkaller.start_time
    rlLog "Syzkaller root: $(cat /var/tmp/syzkaller.root)"
}

function syzkaller_stop() {
    rlRun "tmux kill-session -t syzkaller"
    end_time=$(date +%s)
}

function syzkaller_check_results() {
    # Check test duration
    syzkaller_root=${syzkaller_root:-$(cat /var/tmp/syzkaller.root)}
    syzkaller_workdir=${syzkaller_root}/workdir
    start_time=${start_time:-$(cat /var/tmp/syzkaller.start_time)}
    duration=$((${end_time}-${start_time}))
    rlLog "Test duration was ${duration} seconds."
    if [ "${duration}" -lt "${time}" ]; then
        rlFail "Command ended before timer expired."
    fi

    # Check crash results
    if [ -d "${syzkaller_workdir}/crashes" ] && [ -n "$(ls -A ${syzkaller_workdir}/crashes)" ]; then
        rlFail "Crash results found."
    else
        rlPass "No crash results found."
    fi

    # Check executed syscalls
    rlRun "${syzkaller_root}/bin/syz-db unpack ${syzkaller_workdir}/corpus.db ${syzkaller_workdir}/corpus_dir"
    for call in ${main_syscalls}; do
        syscall=$(echo "${call//\"}" | sed -e 's/,//')
        if grep -q "^${syscall}[$,(]" "${syzkaller_workdir}"/corpus_dir/* ; then
            rlPass "${syscall} executed."
        else
            rlFail "${syscall} not executed."
        fi
    done
}

function syzkaller_cleanup() {
    rlRun "tar cf syzkaller_test_results.tar ${syzkaller_workdir}"
    rlFileSubmit syzkaller_test_results.tar
    rlRun "rm -rf ${syzkaller_workdir}" 0,1
    rlRun "rm -rf ${syzkaller_root}"
    rlRun "rm -f /var/tmp/syzkaller.root /var/tmp/syzkaller.start_time"
    rlRun "ssh $SSH_OPTIONS root@$DUT '[ -f /root/tmp/syzkaller/swap-file ] && swapoff /root/tmp/syzkaller/swap-file'"
    rlRun "ssh $SSH_OPTIONS root@$DUT 'rm -rf /root/tmp/syzkaller'"
}
