#!/usr/bin/bash

BUILDS_URL="${BUILDS_URL:-}"
# shellcheck disable=SC2034
PACKAGE=kpatch
# shellcheck disable=SC2034
SERVICE=kpatch
kpackage=$(rpm -qf /boot/config-$(uname -r) | sed "s/.\$(uname -m)//g; s/core-//g;")
karch=$(rpm -q $kpackage --qf "%{arch}")
knam=$(rpm -q $kpackage --qf "%{name}")
kver=$(rpm -q $kpackage --qf "%{version}")
krel=$(rpm -q $kpackage --qf "%{release}")

OS_RELEASE="/etc/os-release"
LIVEPATCH_TEST_MODULES="/usr/libexec/kselftests/livepatch"

test_fail()
{
    SCORE=${2:-$FAIL}
    echo -e ":: [  FAIL  ] :: Test $1" | tee -a $OUTPUTFILE
    rstrnt-report-result -o "$OUTPUTFILE" "${TEST}/$1" "FAIL" "$SCORE"
}

test_pass()
{
    echo -e "\n:: [  PASS  ] :: Test $1" | tee -a $OUTPUTFILE
    # we don't care how many test passed
    rstrnt-report-result -o "$OUTPUTFILE" "${TEST}/$1" "PASS" 0
}

test_skip()
{
    echo -e "\n:: [  SKIP  ] :: Test $1" | tee -a $OUTPUTFILE
    rstrnt-report-result -o "$OUTPUTFILE" "${TEST}/$1" "SKIP" 0
}

is_rhel()
{
    local rhel_ver=${1:-NULL}
    if grep -q "Red Hat Enterprise Linux ${rhel_ver}" $OS_RELEASE; then
        return 0
    else
        return 1
    fi
}

is_fedora()
{
    if grep -q "Fedora Linux" $OS_RELEASE; then
        return 0
    else
        return 1
    fi
}

is_rhel10()
{
    local ret=0

    is_rhel "10"
    ret=$?
    return $ret
}

is_rhel9()
{
    local ret=0

    is_rhel "9"
    ret=$?
    return $ret
}

is_rhel8()
{
    local ret=0

    is_rhel "8"
    ret=$?
    return $ret
}

package_manage_tool()
{
    if command -v dnf; then
        DNF="$(command -v dnf)"
    elif command -v yum; then
        DNF="$(command -v yum)"
    else
        echo "No dnf or yum found, default to yum"
        DNF="yum"
    fi
}
package_manage_tool

package_install_via_url()
{
    local package=$1
    $DNF install -y -q ${BUILDS_URL}/${knam}/${kver}/${krel}/${karch}/${package}.${karch}.rpm
}

package_install()
{
    local package=$1
    $DNF install -q -y ${package} || package_install_via_url ${package}
}


debug_kernel()
{
    uname -r | grep -E -q "[.+]debug$"
}

dnf_install_modules_internal()
{
    package_install ${knam}-modules-internal-${kver}-${krel}
}

install_kernel_devel()
{
    # Install kernel-devel for its Modules.symvers file
    if debug_kernel; then
        devel="kernel-debug-devel"
    else
        devel="kernel-devel"
    fi
    package_install ${devel}-${kver}-${krel}
}

function download_srpm()
{
    dnf download --source kernel-${kver}-${krel} \
        || wget ${BUILDS_URL}/kernel/${kver}/${krel}/src/kernel-${kver}-${krel}.src.rpm
}

rhel10_build_selftests_modules()
{
    is_rhel "10" && build_selftests_modules
}

build_selftests_modules()
{
    local ret=0

    rpm -q kernel-devel-$(uname -r) || install_kernel_devel
    download_srpm
    rpm -ivh kernel-${kver}-${krel}.src.rpm
    cd $HOME/rpmbuild/SPECS
    dnf builddep -y ./kernel.spec
    rpmbuild -bp kernel.spec

    LIVEPATCH_TEST_MODULES="$HOME/rpmbuild/BUILD/kernel-${kver}-${krel}/linux-${kver}-${krel%%_*}.${karch}/tools/testing/selftests/livepatch"
    cd ${LIVEPATCH_TEST_MODULES}
    if [ "${karch}" == "s390x" ]; then
        OPT="SRCARCH=s390"
    elif [ "${karch}" == "ppc64le" ]; then
        OPT="SRCARCH=powerpc"
    else
        OPT=""
    fi
    make ${OPT}
    ret=$?

    return $ret
}

download_kpatch_repo()
{
    KPATCH_REPO=$1
    KPATCH_REV=$2
    if [ ! -e "kpatch/.git" ]; then
        if [ ! -z "${KPATCH_REV}" ]; then
            rlRun "git clone -b ${KPATCH_REV} ${KPATCH_REPO}" || rlDie
        else
            rlRun "git clone ${KPATCH_REPO}" || rlDie
            pushd kpatch
            KPATCH_REV=$(git describe --tags --abbrev=0)
            rlRun "git checkout ${KPATCH_REV}" || rlDie
            popd
        fi
    fi
}

build_kpatch_setup()
{
    rlRun "git describe --tags"
    rlRun "source test/integration/lib.sh"
    rlRun "kpatch_dependencies"
    rlRun "kpatch_set_ccache_max_size 10G" "0,1"
}

check_test_target()
{
    source /etc/os-release
    MA=$(cut -d '.' -f 1 <<< $VERSION_ID)
    MI=$(cut -d '.' -f 2 <<< $VERSION_ID)
    PREVIOUS_MI=$(( $MI-1 ))
    PREVIOUS_TARGET="${MA}.${PREVIOUS_MI}"
    [ ! -d ${TEST_PATCH_PATH}/${ID}-${VERSION_ID} ] && cp -R ${TEST_PATCH_PATH}/${ID}-${PREVIOUS_TARGET} ${TEST_PATCH_PATH}/${ID}-${VERSION_ID}
}

install_selftests_internal()
{
    rpm -q kernel-selftests-internal && return 0
    if debug_kernel; then
        modules="kernel-debug-modules-internal"
    else
        modules="kernel-modules-internal"
    fi
    # These two appease the net test part of kernel-selftests-internal
    which tc || dnf install -q -y iproute-tc
    package_install bpftool-${kver}-${krel}
    # Livepatch selftests require both modules and scripts
    package_install ${modules}-${kver}-${krel}
    package_install kernel-selftests-internal-${kver}-${krel}
}
