#!/usr/bin/bash

BUILDS_URL="${BUILDS_URL:-}"
# shellcheck disable=SC2034
PACKAGE=kpatch
# shellcheck disable=SC2034
SERVICE=kpatch
kpackage=$(rpm -qf /boot/config-`uname -r` | sed "s/.`uname -m`//g; s/core-//g;")
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

is_rhel9()
{
    rhel_ver=${1:-9}
    if grep -q "Red Hat Enterprise Linux ${rhel_ver}" $OS_RELEASE; then
        return 0
    else
        return 1
    fi
}

is_rhel8()
{
    return $(is_rhel9 8)
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

rhel10_build_selftests_modules()
{
    # Build the test needed modules, for rhel-10 only
    if grep -q 'Red Hat Enterprise Linux 10' /etc/os-release; then
        rpm -q kernel-devel-`uname -r` || install_kernel_devel
        pushd ${LIVEPATCH_TEST_MODULES}
        if [ "${karch}" == "s390x" ]; then
            OPT="SRCARCH=s390"
        elif [ "${karch}" == "ppc64le" ]; then
            OPT="SRCARCH=powerpc"
        else
            OPT=""
        fi
        make -C test_modules ${OPT} modules
        if [ "$?" -ne 0 ]; then
             test_fail "Build the needed modules failed, abort test." && exit 1
        fi
        popd
    fi
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
