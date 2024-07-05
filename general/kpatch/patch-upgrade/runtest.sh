#! /bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of patch-upgrade
#   Description: kpatch-patch upgrade test
#   Update: Chunyu Hu <chuhu@redhat.com>
#           zhijwang <zhijwang@redhat.com>
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

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# trap 'rlFileRestore; exit' SIGHUP SIGINT SIGQUIT SIGTERM
trap 'killall make' SIGHUP SIGINT SIGQUIT SIGTERM

# Include variants from release files
. /etc/os-release

PROC_CMD="/proc/cmdline"
PROC_MEM="/proc/meminfo"
TRACE_FUN="/sys/kernel/debug/tracing/enabled_functions"

KPATCH_REV="${KPATCH_REV:-}"
KPATCH_REPO="${KPATCH_REPO:-https://github.com/dynup/kpatch.git}"
KPATCH_BUILD_OPTS="${KPATCH_BUILD_OPTS:-}"
BUILDS_URL="${BUILDS_URL:-}"
TEST_PATCH_PATH="test/integration"

PATCH_PATH="test/integration/${ID}-${VERSION_ID}"
MOD_A_PATCH1="cmdline-string.patch"
MOD_A_PATCH2="meminfo-string.patch"
MOD_B_PATCH1="data-new.patch"

# Module A/B
KPATCH_MOD_A="livepatch-cmdline-meminfo"
KPATCH_MOD_B="livepatch-meminfo-proc"

karch=$(uname -m)
kver=$(uname -r | cut -f1 -d'-')
krel=$(uname -r | cut -f2 -d'-' | sed -e "s/\.$karch$//" -e "s/\.$karch+debug$//" -e "s/\.$karch.debug$//")
KSRC_RPM=kernel-${kver}-${krel}.src.rpm

function download_src()
{
    URL=${BUILDS_URL}/kernel/${kver}/${krel}/src/${KSRC_RPM}
    rlRun "curl -o ${KSRC_RPM} ${URL}"
}

function compile_module()
{
    kpatch_name=$1
    kpatch_patch=$2
    [ ! -z "${KPATCH_BUILD_OPTS}" ] && compile_flags=${KPATCH_BUILD_OPTS}
    [ -f ../${KSRC_RPM} ] && compile_src="-r ../${KSRC_RPM}"
    rlRun "./kpatch-build/kpatch-build ${compile_flags} ${compile_src} -n ${kpatch_name} ${kpatch_patch}"
}

# Modules check after loading
function module_check_A()
{
    rlRun "cat ${TRACE_FUN} | grep -e cmdline_proc_show -e meminfo_proc_show" "0"
    rlRun "grep kpatch=1 ${PROC_CMD}" "0" "kpatch=1 should exiting in ${PROC_CMD}"
    rlRun "grep VMALLOCCHUNK ${PROC_MEM}" "0" "VMALLOCCHUNK in ${PROC_MEM}"
    rlRun "grep kpatch ${PROC_MEM}" "1" "No kpatch in ${PROC_MEM}"
}

function module_check_B()
{
    local RT=1
    [[ `uname -r` =~ 4.18.0 ]] && RT=0
    rlRun "cat ${TRACE_FUN} | grep meminfo_proc_show" "0"
    rlRun "cat ${TRACE_FUN} | grep cmdline_proc_show" "${RT}"
    rlRun "grep kpatch=1 ${PROC_CMD}" "${RT}"
    rlRun "grep VMALLOCCHUNK ${PROC_MEM}" "1"
    rlRun "grep VmallocChunk ${PROC_MEM}" "0" "VMALLOCCHUNK reverted to lowercase in ${PROC_MEM}"
    rlRun "grep kpatch ${PROC_MEM}" "0" "kpatch: 5 shows in ${PROC_MEM}"
}

# Kpatch install and load modules
function install_load()
{
    module=$1
    kpatch_module=$(sed s/-/_/g <<< ${module})
    rlRun "kpatch install ${module}.ko"
    rlRun "kpatch load ${kpatch_module}"
    rlRun "kpatch list"
}

# Clean installed and loaded kpatch-patch
function clean_installed_loaded()
{
    kpatch force unload --all
    for i in `kpatch list |grep -v "^Loaded\|^Installed\|^$" | awk '{print $1}'`;
    do
        kpatch uninstall $i
    done
}

# Install dependency
function install_dependency()
{
    lists="patchutils\
        kpatch\
        git\
        flex\
        bison\
        openssl-devel\
        dwarves\
        libtraceevent-devel\
        gcc-plugin-devel"
    for i in $lists
    do
        yum -y install $i || dnf -y install $i
    done
}

# Download kpatch git repo
function init_upgrade_test()
{
    if [ ! -e "kpatch/.git" ]; then
        if [ ! -z "$KPATCH_REV" ]; then
            rlRun "git clone -b $KPATCH_REV $KPATCH_REPO" || rlDie
        else
            rlRun "git clone $KPATCH_REPO" || rlDie
            pushd kpatch
            KPATCH_REV=$(git describe --tags --abbrev=0)
            rlRun "git checkout $KPATCH_REV" || rlDie
            popd
        fi
    fi
    pushd kpatch
    rlRun "git describe --tags"
    rlRun "source test/integration/lib.sh"
    rlRun "kpatch_dependencies"
    rlRun "kpatch_set_ccache_max_size 10G"
    source /etc/os-release
    MA=$(cut -d '.' -f 1 <<< $VERSION_ID)
    MI=$(cut -d '.' -f 2 <<< $VERSION_ID)
    PREVIOUS_MI=$(( $MI-1 ))
    PREVIOUS_TARGET="${MA}.${PREVIOUS_MI}"
    [ ! -d ${TEST_PATCH_PATH}/${ID}-${VERSION_ID} ] && cp -R ${TEST_PATCH_PATH}/${ID}-${PREVIOUS_TARGET} ${TEST_PATCH_PATH}/${ID}-${VERSION_ID}
    rlRun "make" || rlDie "build kpatch builder failed ..."
    rlRun "[ -f ${PATCH_PATH}/${MOD_A_PATCH1} ] && cat ${PATCH_PATH}/${MOD_A_PATCH1}" || rlDie "Lacking patches"
    rlRun "[ -f ${PATCH_PATH}/${MOD_A_PATCH2} ] && cat ${PATCH_PATH}/${MOD_A_PATCH2}" || rlDie "Lacking patches"
    rlRun "[ -f ${PATCH_PATH}/${MOD_B_PATCH1} ] && cat ${PATCH_PATH}/${MOD_B_PATCH1}" || rlDie "Lacking patches"
    popd
}

rlJournalStart
    rlPhaseStartSetup
        clean_installed_loaded
        download_src
        rlRun "install_dependency" || rlDie "install depdendecies failed ..."
        init_upgrade_test
    rlPhaseEnd

    rlPhaseStartTest "kpatch-patch upgrade"
        rlRun "pushd kpatch"
        rlRun "mkdir atomic"
        rlRun "combinediff -q --combine ${PATCH_PATH}/${MOD_A_PATCH1} ${PATCH_PATH}/${MOD_A_PATCH2} > atomic/${KPATCH_MOD_A}.patch"
        rlRun "cp ${PATCH_PATH}/${MOD_B_PATCH1} atomic/${KPATCH_MOD_B}.patch"
        rlRun "unset ARCH" 0-255 "power64 can't parse ppc64le when kernel build"
        rlRun "compile_module ${KPATCH_MOD_A} atomic/${KPATCH_MOD_A}.patch"
        rlRun "compile_module ${KPATCH_MOD_B} atomic/${KPATCH_MOD_B}.patch"
        rlRun "install_load ${KPATCH_MOD_A}"
        module_check_A
        rlRun "install_load ${KPATCH_MOD_B}"
        module_check_B
        rlRun "popd"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -rf kpatch/atomic"
        clean_installed_loaded
    rlPhaseEnd

rlJournalEnd
rlJournalPrintText
