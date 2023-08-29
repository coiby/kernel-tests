#!/bin/bash

FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)
TMPDIR=${TMPDIR:-"/tmp"}

function run_cmd
{
    echo ">>> $*"
    eval "$*"
    return $?
}

function get_pkgmgr
{
    [[ -x /usr/bin/dnf ]] && echo "dnf" || echo "yum"
}

function install_dependencies
{
    #
    # XXX: On x86_64, to build libhugetlbfs, both glibc-static.x86_64 and
    #      glibc-static.i686 are required. For details, please refer to:
    #      Bug 1567712 - glibc-static needs to be multilib on RHEL 8
    #
    pkgs=""
    if [[ $(uname -m) == "x86_64" ]]; then
        # 32-bit packages
        pkgs+=" libgcc.i686"
        pkgs+=" glibc-devel.i686"
        pkgs+=" glibc-static.i686"
        # 64-bit packages
        pkgs+=" libgcc.x86_64"
        pkgs+=" glibc-devel.x86_64"
        pkgs+=" glibc-static.x86_64"
    elif [[ $(uname -m) == "s390x" ]]; then
        pkgs+=" libgcc.s390x libgcc.s390"
        pkgs+=" glibc-devel.s390x glibc-devel.s390"
        pkgs+=" glibc-static.s390x glibc-static.s390 "
    else
        pkgs+=" libgcc"
        pkgs+=" glibc-devel"
        pkgs+=" glibc-static"
    fi
    pkgs+=" gcc"

    echo "=== packages to install ==="
    echo $pkgs | tr ' ' '\n'
    pkgmgr=$(get_pkgmgr)
    for pkg in $pkgs; do
        run_cmd rpm --quiet -q $pkg && continue
        run_cmd $pkgmgr -y install $pkgs
    done
}

function build_libhugetlbfs
{
    typeset target=${1?"*** target, e.g. libhugetlbfs-2.21"}

    typeset arch=$(uname -m)
    typeset osmr=$(grep -Go 'release [0-9]\+' /etc/redhat-release | \
                   awk '{print $NF}')
    typeset oa=${osmr}_${arch}
    if [[ $oa != "8_aarch64" && $oa != "8_ppc64le" && $oa != "8_s390x" ]]; then
        #
        # XXX: For RHEL8, add BUILDTYPE=NATIVEONLY to skip 32-bit tests on
        #      64-bit systems
        #
        run_cmd make -C $target BUILDTYPE=NATIVEONLY || return 1
        run_cmd make -C $target PREFIX=/usr BUILDTYPE=NATIVEONLY install || \
                return 1
    else
        run_cmd make -C $target || return 1
        run_cmd make -C $target PREFIX=/usr install || return 1
    fi

    run_cmd cp -f $target/huge_page_setup_helper.py \
                  /usr/bin/huge_page_setup_helper.py
    run_cmd chmod +x /usr/bin/huge_page_setup_helper.py
    return 0
}

PACKAGE_NAME=${1?"***    package name,    e.g. libhugetlbfs"}
PACKAGE_VERSION=${2?"*** package version, e.g. 2.21"}
PACKAGE_URL=${3?"***     package url"}

target=$PACKAGE_NAME-$PACKAGE_VERSION
target_tarball=$(basename $PACKAGE_URL)

echo "------ 01 - Install Dependencies ---------------------------------------"
install_dependencies || exit 1

echo "------ 02 - Download Package -------------------------------------------"
run_cmd rm -f $target_tarball
run_cmd wget -q -O $target_tarball $PACKAGE_URL || exit 1

echo "------ 03 - Extract Package --------------------------------------------"
run_cmd rm -rf $target
run_cmd tar zxf $target_tarball || exit 1

echo "------ 04 - Patch Testsuite --------------------------------------------"
run_cmd bash $CDIR/patch.sh || exit 1

echo "------ 05 - Build Testsuite --------------------------------------------"
build_libhugetlbfs $target || exit 1

echo
echo "OKAY - build test suite $target successfully!!"
echo
exit 0
