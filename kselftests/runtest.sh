#!/bin/bash
# vim: expandtab ts=4 sw=4 ai
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/networking/kselftests
#   Description: kselftests
#   Author: Hangbin Liu <haliu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../cki_lib/libcki.sh || exit 1
. "$CDIR"/../kernel-include/runtest.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1
#-------------------- Setup --------------------
arch=$(uname -m)
version=$(uname -r | cut -f1 -d'-')
release=$(uname -r | cut -f2 -d'-' | sed "s/\.${arch}.*//")
SKIP_CODE=4
TMPDIR=/var/tmp/$(date +"%Y%m%d%H%M%S")
TEST_ITEMS=${TEST_ITEMS:-"default"}
if [ ${DELIVERED_TESTS} ]; then
    EXEC_DIR="/usr/libexec/kselftests"
else
    EXEC_DIR="$TMPDIR/selftests"
fi
# List of selftests to skip.
SKIP_TARGETS=${SKIP_TARGETS:-""}
WAIVE_TARGETS=${WAIVE_TARGETS:-""}
INCLUDE=${INCLUDE:-""}

. "$CDIR"/include/include.sh
for file in $INCLUDE; do
    echo "Loading $file."
    # shellcheck source=/dev/null
    . "$CDIR"/include/$file
done

name="kernel"
if  cki_is_kernel_rt; then
    name="${name}-rt"
fi
if cki_is_kernel_automotive; then
   name="${name}-automotive"
fi
debug_dot=""
if  cki_is_kernel_debug; then
    name="${name}-debug"
    debug_dot=".debug"
fi
function get_pkg_mgr()
{
    if [[ -e /run/ostree-booted ]]; then
      export pkg_mgr="rpm-ostree"
      echo rpm-ostree
    elif [[ -e /usr/bin/dnf ]]; then
      export pkg_mgr="dnf"
      echo dnf
    else
      export pkg_mgr="yum"
      echo yum
    fi
}

[ -d $TMPDIR ] || mkdir $TMPDIR
[ -d $EXEC_DIR ] || mkdir $EXEC_DIR

# Convert parameter line to parameter array
declare -A TEST_PARAM
if [ "${TEST_PARAMS}" ]; then
    OIFS=$IFS
    IFS=";"
    param_array=($TEST_PARAMS)
    for i in "${param_array[@]}"; do
        case_name=$(echo $i | cut -f1 -d' ')
        case_param=$(echo $i | sed "s/${case_name}//")
        [ "${case_name}" ] && TEST_PARAM[${case_name}]="${case_param}"
    done
    IFS=$OIFS
fi

install_packages()
{
    pushd $TMPDIR
    # for 32 bit support
    if [ "${arch}" == "x86_64" ]; then
        $pkg_mgr $pkg_mgr_inst_string glibc-devel.*i686
    fi
    if [ "$UPSTREAM_SOURCE_URL" ]; then
        wget --no-check-certificate $UPSTREAM_SOURCE_URL -O kselftest.tar.gz || test_fail_exit "Fetch Pkg Failed"
        tar zxf kselftest.tar.gz
        pushd linux-kselftest-*/
    else
        pkg=${name}-${version}-${release}
        BASE_URL=${BASE_URL:-"https://cbs.centos.org/kojifiles/packages"}
        BEAKERLIB_rpm_fetch_base_url+=(${BASE_URL})
        rlFetchSrcForInstalled $pkg || test_fail_exit "Fetch Src Failed"
        rpm -ivh --define "_topdir $TMPDIR" ${name/-debug/}-${version}-${release}.src.rpm
        pushd SPECS
        # patch for x86_64 systems. Introduction of efiuki causes dependency to break.
        # per https://issues.redhat.com/browse/ENGCMP-2966 this is only temporary.
        # once this is removed, this patch can also be removed.
        rlRun "sed -i 's/efiuki 1/efiuki 0/' kernel.spec"
        rlRun "yum-builddep --downloadonly -y ./kernel.spec --downloaddir $(pwd)"

        $pkg_mgr $pkg_mgr_inst_string *.rpm
        pushd ../SOURCES
        tar Jxf linux-${version}-${release}.tar.xz
        pushd linux-${version}-${release}/
        extraversion="-${release}.${arch}${debug_dot}"
        sed -i "s/^EXTRAVERSION =.*/EXTRAVERSION = ${extraversion}/" Makefile
    fi
    # to get Module.symvers
    rlRun "$pkg_mgr $pkg_mgr_inst_string ${name}-devel-${version}-${release}"
    symvers=$(rpm -ql "${name}-devel" | grep '\<Module.symvers\>$')
    rlRun "ln -s ${symvers} Module.symvers"
    popd
}

install_kselftests()
{
    modules_extra_pkg=$(K_GetRunningKernelRpmSubPackageNVR modules-extra)
    modules_internal_pkg=$(K_GetRunningKernelRpmSubPackageNVR modules-internal)
    selftests_pkg=$(K_GetRunningKernelRpmSubPackageNVR selftests-internal)
    # Install the selftests-internal, modules-internal packages by default
    if [ "${CKI_SELFTESTS_URL}" ] ; then
        pushd ${EXEC_DIR}
        wget --no-check-certificate $CKI_SELFTESTS_URL -O kselftest.tar.gz || \
            { rlLog "Wget CKI_SELFTESTS_URL failed" && return 1; }
        tar zxf kselftest.tar.gz
        rlLog "Upstream ${TEST} installed..."
        popd
    elif [ "${BUILD_FROM_SRC}" ] ; then
        # Install debug-modules-extra
        if ! rpm --quiet -q "${modules_extra_pkg}"; then
            rlRpmDownload "${modules_extra_pkg}.${arch}"
            rlRun "$pkg_mgr $pkg_mgr_inst_string ./${modules_extra_pkg}.${arch}.rpm"
        fi
        if ! rpm --quiet -q "${modules_internal_pkg}"; then
            rlRpmDownload "${modules_internal_pkg}.${arch}"
            rlRun "$pkg_mgr $pkg_mgr_inst_string ./${modules_internal_pkg}.${arch}.rpm"
        fi
        if [ "${UPSTREAM_SOURCE_URL}" ]; then
            pushd $TMPDIR/linux-kselftest-*/
        else
            pushd $TMPDIR/SOURCES/linux-${version}-${release}/
        fi
        yes "" | make config
        # for bpf build
        # Some bpf tests rely on vmlinux need to remove rhel.pem and use "modules" macro
        # to build both vmlinux and modules_prepare in one command.
        # sed -i "s/CONFIG_SYSTEM_TRUSTED_KEYS=\"certs\/rhel.pem\"/CONFIG_SYSTEM_TRUSTED_KEYS=\"\"/" .config
        #
        # Reverting changes made previously for bpf module build.
        # Now using delivered bpf which works well and changes did not completely fix module issue.
        # Leaving previous comments as a reminder if we need to try to build bpf again.
        make -j$(nproc) modules_prepare
        sed -i "s/^SKIP_TARGETS.*/#SKIP_TARGETS ?= /" tools/testing/selftests/Makefile
        make -j$(nproc) -C tools/testing/selftests install TARGETS="${TEST_ITEMS}" INSTALL_PATH=${EXEC_DIR}
        rlLog "Compiled ${TEST} installed..."
        popd
        [ -f $TMPDIR/selftests/run_kselftest.sh ] && return 0 || return 1
    else
        if ! rpm --quiet -q "${modules_extra_pkg}"; then
            # Install debug-modules-extra
            rlRpmDownload "${modules_extra_pkg}.${arch}"
            rlRun "$pkg_mgr $pkg_mgr_inst_string ./${modules_extra_pkg}.${arch}.rpm"
        fi
        if ! rpm --quiet -q "${modules_internal_pkg}"; then
            rlRpmDownload "${modules_internal_pkg}.${arch}"
            rlRun "$pkg_mgr $pkg_mgr_inst_string ./${modules_internal_pkg}.${arch}.rpm"
        fi
        if ! rpm --quiet -q "${selftests_pkg}"; then
            rlRpmDownload "${selftests_pkg}.${arch}"
            rlRun "$pkg_mgr $pkg_mgr_inst_string ./${selftests_pkg}.${arch}.rpm"
        fi
        if [ $pkg_mgr == "rpm-ostree" ]; then
            rlRun "cp -r /usr/libexec/kselftests/* ${EXEC_DIR}"
        fi
        if rpm -q "${selftests_pkg}"; then
            rlLog "Delivered ${TEST} installed..."
            return 0
        else
            # CKI don't build kselftest rpm for none x86. Let's report SKIP directly
            [ ${arch} != "x86_64" ] && test_skip_exit "install kselftests failed on none x86 arch"
            return 1
        fi
    fi
}

function NormalizeTestItems()
{
    item=$1
    total_tests=""
    grep -qE "^${item}(:|$)" ${EXEC_DIR}/kselftest-list.txt || \
        { test_skip "$item test not found in kselftest-list.txt"; }
    #add echo because += does not add white space to the end or begining of lists it processes.
    total_tests+=$(echo " " $(grep -E "^${item}(:|$)" ${EXEC_DIR}/kselftest-list.txt))
    TARGETS=${total_tests}
}

function RunKSelfTest()
{
    local testscript="$1"
    local test_folder="$(echo ${testscript}|cut -d : -f 1)"
    local test_case="$(echo ${testscript}|cut -d : -f 2)"
    local ret

    OUTPUTFILE=$(new_outputfile)

    # check if the test is to be ignored
    check_skip "$testscript" && rlLog "=== Skipping: $testscript" && return $SKIP_CODE

    # clear dmesg before each test
    dmesg -C

    # run the self-test script
    rlLog "=== Running: $testscript"
    pushd $EXEC_DIR/${test_folder}
    ./${test_case} ${TEST_PARAM[${testscript}]} |& tee $OUTPUTFILE
    ret=${PIPESTATUS[0]}
    popd

    return $ret
}

function SetupTest ()
{
    rlPhaseStartSetup
    pkg_mgr=$(get_pkg_mgr)
    if [[ $pkg_mgr == "rpm-ostree" ]]; then
      echo "pkg_mgr = RPM OSTREE"
      export pkg_mgr_inst_string="-A -y --idempotent --allow-inactive install"
      export EXEC_DIR="$TMPDIR/selftests"
      [ -d ${EXEC_DIR} ] || mkdir -p ${EXEC_DIR}
      rlRun "rpm-ostree ex apply-live --allow-replacement"
      if ! rpm -q --quiet epel-release; then
        $pkg_mgr $pkg_mgr_inst_string \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-"${krelease:?}".noarch.rpm
      fi
    else
      export pkg_mgr_inst_string="-y install"
    fi
    if [ "${BUILD_FROM_SRC}" ]; then
        rlRun install_packages
        # do patches
        for item in $TEST_ITEMS; do
            _item=$(echo $item | tr \/ \_)
            if type do_${_item}_patch >& /dev/null; then
                rlRun do_${_item}_patch
            fi
        done
    fi
    rlRun install_kselftests || test_fail_exit "install kselftests failed"
    submit_log "$EXEC_DIR/kselftest-list.txt"
    rlPhaseEnd
}

function RunTest ()
{
    local ret
    for item in $TEST_ITEMS; do
        # Check if test exist before do config and run
        if ! check_test_exist "$item"; then
            test_warn "$item test not found in kselftest-list.txt"
            continue
        fi

        rlPhaseStartTest $item
        rlLog "Test Start Time: $(date)"
        # do setup
        _item=$(echo $item | tr \/ \_)
        if type do_${_item}_config >& /dev/null; then
            rlRun do_${_item}_config
        fi

        if type do_${_item}_run >& /dev/null; then
            rlRun do_${_item}_run
        else
            # create list of tests to run
            if [ "${TEST_ITEMS}" == "default" ]; then
                TARGETS=$(${EXEC_DIR}/run_kselftest.sh -l)
            else
                NormalizeTestItems $item
            fi
            total_num=$(echo ${TARGETS} | wc -w)
            num=0
            # Run self-tests
            for t in ${TARGETS}; do
                num=$(($num + 1))
                RunKSelfTest ${t}
                ret=$?
                check_result $num $total_num ${t} $ret
            done
        fi

        # do reset
        if type do_${_item}_reset >& /dev/null; then
            rlRun do_${_item}_reset
        fi
        rlLog "Test End Time: $(date)"
        rlPhaseEnd
    done
}

function CleanupTest ()
{
    rlPhaseStartCleanup
    rlRun "pushd '$HOME'"

    rlRun "rm -rf $TMPDIR"

    rlPhaseEnd
}

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then

    rlJournalStart

        SetupTest
        RunTest
        CleanupTest

    rlJournalEnd
fi
