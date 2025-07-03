#! /bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of compat
#   Description: Kpatch compat with ftrace kprobe perf stap crash
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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

. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../include/lib.sh
. ../include/lib_build.sh
. ../../../security/crypto/enable_fips/lib.sh

trap 'killall make; kill runtest.sh' SIGHUP SIGINT SIGQUIT SIGTERM

#  When using rpm
KPATCH_PATCH="${KPATCH_PATCH:-}"
KPATCH_PATH="/home/kpatch-patch-modules"
KPATCH_MODULE=""
TEST_CMD="${TEST_CMD:-cat /proc/meminfo}"
GREP_STR="${GREP_STR:-kpatch:         5}"
KPATCH_TARGET_FUNCTION=${KPATCH_TARGET_FUNCTION:-meminfo_proc_show}
BUILDS_URL="${BUILDS_URL:-}"
NFS_SHARE=${NFS_SHARE:-}
KPATCH_LOCATION=${KPATCH_LOCATION:-"/data/kpatch"}
KPATCH_SHARE="${NFS_SHARE}:${KPATCH_LOCATION}"
KPATCH_MNT="/mnt/kpatch"
PACKAGE="kernel kpatch crash systemtap"
MOUNT_FLAG=0


function install_kpp_debuginfo()
{
    # Example of a kpatch-patch pkg "kpatch-patch-4_18_0-107-0-1.test.el8"
    local kpp_pkg kpp_debuginfo_pkg kpp_name kpp_version kpp_release kpp_arch
    kpp_pkg=$1

    # Example of a kpatch-patch debuginfo pkg "kpatch-patch-4_18_0-107-debuginfo-0-1.test.el8.x86_64"
    kpp_debuginfo_pkg=$(echo "$kpp_pkg" | sed 's/-/-debuginfo-/4')

    kpp_name=$(rpm -q --queryformat "%{NAME}" $kpp_pkg)
    kpp_version=$(rpm -q --queryformat "%{VERSION}" $kpp_pkg)
    kpp_release=$(rpm -q --queryformat "%{RELEASE}" $kpp_pkg)
    kpp_arch=$(rpm -q --queryformat "%{ARCH}" $kpp_pkg)
    rpm -q "${kpp_debuginfo_pkg}" || \
        yum install -y "${BUILDS_URL}/${kpp_name}/${kpp_version}/${kpp_release}/${kpp_arch}/${kpp_debuginfo_pkg}.${kpp_arch}.rpm"
}

trace_dir="/sys/kernel/debug/tracing"
func_filter="${trace_dir}/set_ftrace_filter"
trace_res="${trace_dir}/trace"
kprobe_trace="${trace_dir}/kprobe_events"
kprobe_enable="${trace_dir}/events/kprobes/enable"
tracer="${trace_dir}/current_tracer"

function install_deps() {
    # need to pass brew url to BUILDS_URL
    package_install perf-${kver}-${krel}
    install_debuginfo
    install_kernel_devel

    for i in $PACKAGE; do
        package_install $i
    done
}

function setup_ftrace() {
    rlRun "echo ${KPATCH_TARGET_FUNCTION} > ${func_filter}"
    rlRun "echo function > ${tracer}"
}

# shellcheck disable=SC2120
function setup_crash() {
    symbol=${1:-${KPATCH_TARGET_FUNCTION}}
    symbol_addr=$(cat /proc/kallsyms | grep ${symbol} | grep ${KPATCH_MODULE//-/_} | awk '{print $1}')
    src_result=~/source
    crash_cmd=crash.cmd

    cat > $crash_cmd << EOF
mod | grep kpatch | awk '{print $2}' > ~/kpatch_mods
mod -s ${KPATCH_MODULE//-/_} ${KPATCH_PATH}/${KPATCH_MODULE}.ko
mod -s kpatch
sym ${symbol}
dis -sl ${symbol_addr} > ${src_result}
l ${symbol} >> ${src_result}
exit
EOF
}

function setup_perf() {
    eval perf probe --add '${KPATCH_TARGET_FUNCTION}'
}

function setup_kprobe() {
    rlRun "echo \"p ${KPATCH_MODULE//-/_}:${KPATCH_TARGET_FUNCTION}\" > ${kprobe_trace}"
}

function setup_stap() {
    if fipsIsEnabled; then
        export STAP_FIPS_OVERRIDE=1;
        rlLog "Run SystemTap with enabled FIPS mode."
    fi
    rlRun "stap -ve 'probe kernel.function(\"${KPATCH_TARGET_FUNCTION}\") {printf(\"hello\")}' -c '${TEST_CMD}' | grep \"${GREP_STR}\""
}

function reset_trace_probes() {
    rlRun "echo nop > ${tracer}"
    rlRun "echo 0 > ${trace_dir}/events/enable"
    rlRun "echo > ${trace_dir}/kprobe_events"
    rlRun "echo > ${func_filter}"
}

rlJournalStart
    rlPhaseStartSetup
        install_deps
        rlShowPackageVersion ${PACKAGE}
        if [ -z "${KPATCH_PATCH}" ]; then
            KPATCH_MODULE="test-data-new"
        else
            KPATCH_PATH="/usr/lib/kpatch/$(uname -r)"
            KPATCH_MODULE=$(echo ${KPATCH_PATCH} | sed -e "s/kpatch-patch/kpatch/" | sed -e "s/\.test.*/_test/")
            rlRun "install_kpp_debuginfo ${KPATCH_PATCH}"
        fi
        if [ -d ${KPATCH_PATH} ] && ls ${KPATCH_PATH}/*ko > /dev/null ; then
            echo "Test module is existed"
        elif ! mount | grep mnt/kpatch; then
            mount -t nfs "${KPATCH_SHARE}" "${KPATCH_MNT}" && { MOUNT_FLAG=1; echo "succeeded"; } || echo "failed"
            KPATCH_PATH="${KPATCH_MNT}/$(uname -r)"
        else
            echo "Already mounted $(mount | grep kpatch)"
        fi
        # Unload all loaded kpatch-patch modules if test is not clean.
        rlRun "kpatch force unload --all"

        ! test -e /usr/lib/kpatch/$(uname -r)/ &&  \
        rlRun "mkdir -p /usr/lib/kpatch/$(uname -r)/"

        # If no kpatch-patch rpm availabe, then assume we use self-built kpatch-patch
        # This is not precise, but work for use case.
        if ! kpatch list | grep ${KPATCH_MODULE//-/_}; then
            rlRun "kpatch install ${KPATCH_PATH}/${KPATCH_MODULE}.ko" || rlDie "Can't install ${KPATCH_MODULE}"
            kpatch_install=1
        fi

        rlRun "kpatch load --all"
    rlPhaseEnd

    rlPhaseStartTest "Kpatch compat with perf"
        setup_perf
        rlRun "kpatch list | grep ${KPATCH_MODULE//-/_}"
        rlRun "perf stat -e probe:${KPATCH_TARGET_FUNCTION}  -- ${TEST_CMD} 2>&1| grep \"1.*probe:${KPATCH_TARGET_FUNCTION%%_*}\" -o"
        rlRun "perf probe --del \"probe:${KPATCH_TARGET_FUNCTION}\""
    rlPhaseEnd

    rlPhaseStartTest "Kpatch compat with kprobe"
        setup_kprobe
        rlRun "kpatch list | grep ${KPATCH_MODULE//-/_}"
        # this should fail as only one of kpatch and kprobe can pin the smae func.
        rlRun "echo 1 > ${kprobe_enable}" 0
        rlRun "${TEST_CMD} | grep \"${GREP_STR}\""
        # this should fail as only one of kpatch and kprobe can pin the smae func.
        rlRun "cat ${trace_res} | grep ${KPATCH_TARGET_FUNCTION}" 0
        # shellcheck disable=SC2188
        > ${trace_res}
    rlPhaseEnd

    rlPhaseStartTest "Kpatch compat with ftrace"
        setup_ftrace
        # shellcheck disable=SC2188
        > ${trace_res}
        rlRun "kpatch list | grep ${KPATCH_MODULE//-/_}"
        rlRun "${TEST_CMD} | grep \"${GREP_STR}\""
        rlRun "cat ${trace_res} | grep \"${KPATCH_TARGET_FUNCTION} <\""
    rlPhaseEnd

    rlPhaseStartTest "Kpatch compat with live crash"
        setup_crash
        rlRun "kpatch list | grep ${KPATCH_MODULE//-/_}"
        rlRun "crash -i ${crash_cmd} /usr/lib/debug/lib/modules/$(uname -r)/vmlinux"
        rlRun "grep \"${GREP_STR}\" ~/source" 0-255
        rlRun -l "cat ~/source" 0-255
    rlPhaseEnd

    rlPhaseStartTest "Kpatch compat with stap"
        rlRun "kpatch list | grep ${KPATCH_MODULE//-/_}"
        setup_stap
    rlPhaseEnd

    rlPhaseStartCleanup
        reset_trace_probes
        [[ ! -z ${kpatch_install} ]] && rlRun "kpatch force unload ${KPATCH_MODULE//-/_}; kpatch uninstall ${KPATCH_MODULE//-/_}"
        [ ${MOUNT_FLAG} == 1 ] && umount ${KPATCH_MNT}
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
