#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source beaker environment
set +x
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/../../cki_lib/libcki.sh || exit 1
set -x

# shellcheck disable=SC2155
export rhel_major=$(grep -o '[0-9]*\.[0-9]*' /etc/redhat-release | awk -F '.' '{print $1}')

if stat /run/ostree-booted > /dev/null 2>&1; then
  PKGMGR="rpm-ostree -Ay --idempotent --allow-inactive install"
elif [[ -x /usr/bin/dnf ]]; then
  PKGMGR="dnf -y --skip-broken install"
else
  PKGMGR="yum -y --skip-broken install"
fi
export PKGMGR

function rt_package_install()
{
    # install RT packages
    if [ "$rhel_major" -eq 7 ]; then
        packages="rt-tests rt-setup rteval rteval-loads rtcheck tuned-profiles-realtime tuna"
    elif [ "$rhel_major" -eq 8 ]; then
        packages="rt-tests rt-setup rteval rteval-loads tuned-profiles-realtime tuna"
    else
        packages="realtime-tests realtime-setup rteval rteval-loads tuned-profiles-realtime tuna stress-ng stalld"
    fi
    echo "install needed package $packages" | tee -a "$OUTPUTFILE"

    for i in $packages; do
        if rpm -q --quiet "$i" ; then
            continue
        else
            $PKGMGR "$i"
        fi
    done

    # install additional standard packages
    $PKGMGR  bc curl gcc gdb git patch pciutils rpm-build strace time unzip wget zip
    if [ "$rhel_major" -eq 8 ]; then
        $PKGMGR python36 python3-pip
    elif [ "$rhel_major" -ge 9 ]; then
        $PKGMGR python3 python3-pip
    fi
}

function rt_env_setup()
{
    kernel_name=$(uname -r)
    if [[ $kernel_name =~ "rt" ]] || cki_is_kernel_automotive; then
        echo "running the $kernel_name" | tee -a "$OUTPUTFILE"
        rt_package_install
    else
        echo "non rt kernel, please use rt kernel" | tee -a "$OUTPUTFILE"
        rstrnt-report-result "$TEST" SKIP
        exit
    fi
}
