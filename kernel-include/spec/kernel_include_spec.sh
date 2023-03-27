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
