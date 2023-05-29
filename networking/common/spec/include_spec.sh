#!/bin/bash
eval "$(shellspec - -c) exit 1"

export RSTRNT_JOBID="1234"

Include networking/common/include.sh

export RPM_KERNEL_VERION="5.14.0-234.el9.x86_64"
export TARBALL_KERNEL_VERION="6.2.0-rc3"

Mock rpm
    if [ "$*" == "-qf /boot/config-${TARBALL_KERNEL_VERION}" ]; then
        # simulate the kernel version is not from rpm
        echo "tarball"
        exit 1
    fi
    if [ "$*" == "-qf /boot/config-${RPM_KERNEL_VERION}" ]; then
        # simulate the kernel version is installed as rpm
        echo "kernel-core-${RPM_KERNEL_VERION}"
        exit 0
    fi
    # by default just print the commnad
    echo "rpm $*"
End

Mock uname
    if [ "$1" == "-r" ]; then
        echo "${KERNEL_VERSION}"
    else
        echo "uname $*"
    fi
    exit 0
End

Describe 'networking/common/include'
    Parameters
        "${RPM_KERNEL_VERION}" rpm
        "${TARBALL_KERNEL_VERION}" tarball
    End

    It "can install_required_packages $1 ($2)"
        # Mock function
        kernel_modules_extra_install(){
            true
        }
        export KERNEL_VERSION=${1}
        When call install_required_packages
        # it moves to /etc/pki/ca-trust/source/anchors to download RH certificates...
        if [ "$2" == "rpm" ]; then
            The stdout should include "yum info kernel-modules-extra"
            The stdout should include "yum install kernel-modules-extra -y --skip-broken"
        fi
        if [ "$2" == "tarball" ]; then
            The stdout should not include "yum info kernel-modules-extra"
            The stdout should not include "yum install kernel-modules-extra -y --skip-broken"
        fi
        The status should be success
    End
End
