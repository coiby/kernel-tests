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
ignore_crash_patterns=${ignore_crash_patterns:-""}
git_patches=${git_patches:-""}
syzkaller_root=${syzkaller_root:-"/root/tmp/syzkaller_root/syzkaller"}
syzkaller_workdir=${syzkaller_root}/workdir

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

# syscalls returning ENOSYS in QM
not_present_syscalls=${not_present_syscalls:-''}

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
    "no_mutate_syscalls": [${support_syscalls}],
    "ignores": [${ignore_crash_patterns}]
}
EOF
    [ -e syzkaller.conf ] && return 0 || return 1
}

function create_syzkaller_qm_config() {
    local syscalls="${main_syscalls}${support_syscalls:+, ${support_syscalls}}"
    cat <<EOF > syzkaller.conf
{
    "http": "127.0.0.1:56741",
    "rpc": "127.0.0.1:56742",
    "max_crash_logs" : 10,
    "target": "linux/${arch}",
    "syzkaller": "${syzkaller_root}",
    "cover": false,
    "type": "none",
    "reproduce": false,
    "workdir": "${syzkaller_workdir}",
    "enable_syscalls": [${syscalls}],
    "disable_syscalls": [${disable_syscalls}],
    "no_mutate_syscalls": [${support_syscalls}],
    "ignores": [${ignore_crash_patterns}]
}
EOF
    [ -e syzkaller.conf ] && return 0 || return 1
}

function setup_qm() {
    rlRun "mkdir -p /etc/containers/systemd/qm.container.d"
    cat <<EOF > /etc/containers/systemd/qm.container.d/syzkaller.conf
[Container]
Volume=${syzkaller_root}:${syzkaller_root}:z
EOF
    rlRun "checkmodule -M -m -o syzkaller.mod ${CDIR}/qm/syzkaller.te"
    rlRun "semodule_package -o syzkaller.pp -m syzkaller.mod"
    rlRun "semodule -i syzkaller.pp"
    rlRun "systemctl daemon-reload"
    rlRun "systemctl restart qm"
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
    if [ -n "$FUZZ_IN_QM" ]; then
        rlRun "git apply ${CDIR}/qm/qm.patch"
    fi
    for git_patch in $git_patches; do
        rlRun "git apply ${CDIR}/$git_patch"
    done
    rlRun make

    # Create config
    if [ -z "$FUZZ_IN_QM" ]; then
        rlRun create_syzkaller_config
    else
        rlRun create_syzkaller_qm_config
        rlRun "mkdir -p ${syzkaller_workdir}"
        rlRun "cp /usr/lib64/libstdc++.so.6 /usr/lib/qm/rootfs/usr/lib64/"
        rlRun setup_qm
    fi
    rlFileSubmit syzkaller.conf
}

function syzkaller_start() {
    # Run syzkaller in the background
    start_time=$(date +%s)
    if [ -z "$FUZZ_IN_QM" ]; then
        rlRun "tmux new-session -d -s syzkaller '${syzkaller_root}/bin/syz-manager ${verbose} -config ${syzkaller_root}/syzkaller.conf 2>&1 | tee /var/tmp/syz-manager_run.log'"
    else
        rlRun "tmux new-session -d -s syz-manager \"podman exec -it qm ${syzkaller_root}/bin/syz-manager ${verbose} -config ${syzkaller_root}/syzkaller.conf 2>&1 | tee /var/tmp/syz-manager_run.log\""
        # wait for syz-manager to start
        while ! grep -q "skipped [0-9]* seeds" /var/tmp/syz-manager_run.log; do
            sleep 2
        done
        rlRun "tmux new-session -d -s syz-executor \"podman exec -it qm bash -c \\\"cd ${syzkaller_workdir}; ${syzkaller_root}/bin/linux_arm64/syz-executor runner 0 127.0.0.1 56742\\\" 2>&1 | tee /var/tmp/syz-executor_run.log\""
        # wait for the swap-file to be present before resizing and mounting
        while [ ! -f "${syzkaller_workdir}/swap-file" ]; do
            sleep 1
        done
        rlRun "dd if=/dev/zero of=${syzkaller_workdir}/swap-file bs=1M count=1024 conv=notrunc"
        rlRun "mkswap ${syzkaller_workdir}/swap-file"
        rlRun "swapon ${syzkaller_workdir}/swap-file"
    fi
    echo $start_time > /var/tmp/syzkaller.start_time
    if [ -n "${not_present_syscalls}" ]; then
        rlLog "Waiting for syzkaller to start before checking for not present syscalls..."
        while ! grep -q "machine check:" /var/tmp/syz-manager_run.log; do
            sleep 2
        done
        sleep 10
        for call in ${not_present_syscalls}; do
            syscall=$(echo "${call//\"}" | sed -e 's/,//')
            if grep -q "syscall ${syscall} is not present" /var/tmp/syz-manager_run.log; then
                rlPass "${syscall} not present as expected."
            else
                rlFail "${syscall} in not_present_syscalls list, but it is present. Refusing to continue."
                syzkaller_stop
                rlRun "semodule -r syzkaller"
                exit 1
            fi
        done
    fi
}

function syzkaller_stop() {
    if [ -z "$FUZZ_IN_QM" ]; then
        rlRun "tmux kill-session -t syzkaller"
    else
        rlRun "tmux kill-session -t syz-manager"
        rlRun "tmux kill-session -t syz-executor"
        rlFileSubmit /var/tmp/syz-executor_run.log
    fi
    rlFileSubmit /var/tmp/syz-manager_run.log
    end_time=$(date +%s)
}

function syzkaller_run() {
    start_time=$(date +%s)
    if [ -z "$FUZZ_IN_QM" ]; then
        rlWatchdog "${syzkaller_root}/bin/syz-manager ${verbose} -config ${syzkaller_root}/syzkaller.conf" "${time}"
    else
        rlRun syzkaller_start
        rlRun "sleep ${time}"
        rlRun syzkaller_stop
    fi
    end_time=$(date +%s)
}

function syzkaller_check_results() {
    # Sanitize not_present_syscalls to have all entries separated by spaces
    local not_present_syscalls_sanitized=$(echo "${not_present_syscalls}" | tr ',\n\r\t"'"'" ' ' | tr -s ' ')

    # Check test duration
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
        if [[ " ${not_present_syscalls_sanitized} " == *" ${syscall} "* ]]; then
            rlLog "${syscall} not present."
        else
            find_syscall_ret=$(python ${CDIR}/find_syscall_in_corpus.py "${syzkaller_workdir}/corpus_dir" "$syscall")
            if [ "$find_syscall_ret" = "executed" ]; then
                rlPass "${syscall} executed."
            elif [ "$find_syscall_ret" = "not executed" ]; then
                rlFail "${syscall} not executed."
            else
                rlFail "Error while finding $syscall in corpus: $find_syscall_ret"
            fi
        fi
    done
}

function syzkaller_cleanup() {
    if [ -n "$FUZZ_IN_QM" ]; then
        rlRun "swapoff ${syzkaller_workdir}/swap-file"
        rlRun "rm -f ${syzkaller_workdir}/swap-file"
        rlRun "semodule -r syzkaller"
        rlRun "rm -f /etc/containers/systemd/qm.container.d/syzkaller.conf"
        rlRun "systemctl daemon-reload"
        rlRun "systemctl restart qm"
    else
        rlRun "ssh $SSH_OPTIONS root@$DUT '[ -f /root/tmp/syzkaller/swap-file ] && swapoff /root/tmp/syzkaller/swap-file'"
    fi
    rlRun "tar cf syzkaller_test_results.tar ${syzkaller_workdir}"
    rlFileSubmit syzkaller_test_results.tar
    rlRun "rm -rf ${syzkaller_workdir}" 0,1
    rlRun "rm -rf ${syzkaller_root}"
    rlRun "rm -f /var/tmp/syzkaller.start_time"
    rlRun "ssh $SSH_OPTIONS root@$DUT 'rm -rf /root/tmp/syzkaller'"
}
