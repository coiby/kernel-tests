#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
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
TYPE=${TYPE:-"isolated"}
local_dir=${local_dir:-"/root/tmp"}
IMAGE=${IMAGE:-""}
SANDBOX=${SANDBOX:-"none"}
cover=${cover:-"false"}
timer=${timer:-3600}
commit=${commit:-"21339d7b9986698282dce93709157dc36907fbf8"}
repro=${repro:-"false"}
syscalls=${syscalls:-'"lsetxattr$security_ima", "geteuid", "getresuid", "getegid", "getgid", "getgroups", "getresgid", "newfstatat"'}

create-test-cfg()
{
    local image vm_param
    local targets=$(echo "$1" | awk -F' ' '{for(i=1;i<=NF;i++){printf "\"%s\", ", $i}}' | sed 's/, $//')
    arch=$(uname -m|sed 's/x86_/amd/g'|sed 's/aarch/arm/g')

    if [ "$TYPE" == "isolated" ]; then
        image=""
        vm_param="\"targets\" : [ ${targets} ], \"target_dir\" : \"${local_dir}/syzkaller-client\""
    elif [ "$TYPE" == "qemu" ]; then
        [ "$REPRODUCE" ] && repro="true"
        image="\"image\": \"${IMAGE}\","
        vm_param='"count": 8, "cpu": 2, "mem": 2048'
    fi
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
    ],
    "syzkaller": "/root/syzkaller/",
    "sandbox": "${SANDBOX}",
    "cover": ${cover},
    "reproduce": ${repro},
    ${image}
    "type": "${TYPE}",
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
        rlRun "${pkg_mgr} ${pkg_mgr_rmv_string} glibc-static"
        rlRun "pushd /root"
        rlRun "git clone https://github.com/google/syzkaller"
        rlRun "pushd syzkaller"
        rlRun "make"
        soc_ip=$(nmcli | grep -A1 "ip4 default" | grep -v "ip4 default" | awk '{print $2}' | awk -F "/" '{print $1}')
        # create config file:
        rlRun "create-test-cfg ${soc_ip}"
        rlFileSubmit syzkaller-test.cfg
        rlRun "popd"
        rlRun "ssh-keygen -q -t ed25519 -N '' <<< $'\ny' > /dev/null 2>&1"
        rlRun "cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys"
    rlPhaseEnd
    rlPhaseStartTest
        start_time=$(date +%s)
        rlWatchdog "/root/syzkaller/bin/syz-manager -config /root/syzkaller/syzkaller-test.cfg" "${timer}"
        end_time=$(date +%s)
        duration=$((${end_time}-${start_time}))
                rlLog "Test duration was ${duration} seconds."
        if [ "${duration}" -lt "${timer}" ]; then
            rlFail "Command ended before timer expired."
        fi
        if [ -d "${local_dir}/syz-manager-logs/crashes" ] && [ "$(ls -l "${local_dir}/syz-manager-logs/crashes")" != "total 0" ]; then
            rlFail "Crash results found."
        else
            rlPass "No crash results found."
        fi
        # Additional verification that all syscalls were executed.
        rlRun "mkdir ${local_dir}/corpus_dir"
        rlRun "/root/syzkaller/bin/syz-db unpack ${local_dir}/syz-manager-logs/corpus.db ${local_dir}/corpus_dir"
        for call in ${syscalls}; do
            syscall=$(echo "${call//\"}" | sed -e 's/,//')
            if grep -q "^${syscall}[$,(]" "${local_dir}"/corpus_dir/* ; then
                rlPass "${syscall} executed."
            else
               rlFail "${syscall} not executed."
            fi
        done
        rlRun "dmesg > dmesg-syscalls.log"
        rlFileSubmit dmesg-syscalls.log
    rlPhaseEnd
    rlPhaseStartCleanup
        rlRun "tar cvf syzkaller_test_results.tar ${local_dir}"
        rlFileSubmit syzkaller_test_results.tar
        rlRun "rm -rf /root/syzkaller"
        rlRun "rm -rf /root/go"
        rlRun "rm -rf ${local_dir}" 0,1
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
