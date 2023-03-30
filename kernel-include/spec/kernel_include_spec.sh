#!/bin/bash
eval "$(shellspec - -c) exit 1"

Include "kernel-include/runtest.sh"

Describe 'kernel-include: K_GetRunningKernelRpmVersionRelease'
    Mock rpm
        echo "rpm $*"
        if [[ -z ${kernel_version:-} ]]; then
            exit 1
        fi
    End
    Mock uname
        echo "${kernel_version}"
    End
    It "can get kernel version release"
        export kernel_version="6.0.7-300.fc36.x86_64"
        When call K_GetRunningKernelRpmVersionRelease
        The first line should equal "rpm -q --queryformat %{version}-%{release} -qf /boot/config-${kernel_version}"
        The status should be success
    End
    It "fails if it cannot get the kernel version release"
        export kernel_version=
        When call K_GetRunningKernelRpmVersionRelease
        The first line should equal "rpm -q --queryformat %{version}-%{release} -qf /boot/config-${kernel_version}"
        The status should be failure
    End
End

Describe 'kernel-include: K_GetRunningKernelRpmName'
    Parameters
        kernel kernel
        kernel-core kernel
        kernel-debug kernel-debug
        kernel-rt kernel-rt
        kernel-rt-core kernel-rt
        kernel-rt-debug kernel-rt-debug
        kernel-64k kernel-64k
        kernel-64k-core kernel-64k
        kernel-64k-debug kernel-64k-debug
    End
    Mock rpm
        echo "$PKG_NAME"
    End
    It "can get kernel rpm name for $1"
        export PKG_NAME=$1
        export KERNEL_NAME=$2
        When call K_GetRunningKernelRpmName
        The first line should equal "${KERNEL_NAME}"
        The status should be success
    End
End
