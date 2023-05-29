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

Describe 'kernel-include: K_GetRunningKernelSrpmName'
    Parameters
        kernel-5.14.0-289.el9.src.rpm 5.14.0-289.el9 kernel
        kernel-rt-4.18.0-479.rt7.268.el8.src.rpm 4.18.0-479.rt7.268.el8 kernel-rt
    End
    Mock rpm
        echo "$SRPM"
    End
    Mock K_GetRunningKernelRpmVersionRelease
        echo "$KERNEL_VR"
    End
    It "can get kernel rpm name for $1"
        export SRPM="$1"
        export KERNEL_VR="$2"
        export KERNEL_NAME="$3"
        When call K_GetRunningKernelSrpmName
        The first line should equal "${KERNEL_NAME}"
        The status should be success
    End
End

Describe 'kernel-include: K_GetRunningKernelRpmSubPackageNVR'
    Parameters
        # devel
        kernel kernel 5.14.0-291.el9 devel kernel-devel-5.14.0-291.el9
        kernel kernel-debug 5.14.0-291.el9 devel kernel-debug-devel-5.14.0-291.el9
        kernel kernel-rt 5.14.0-291.el9 devel kernel-rt-devel-5.14.0-291.el9
        kernel kernel-rt-debug 5.14.0-291.el9 devel kernel-rt-debug-devel-5.14.0-291.el9
        kernel-rt kernel-rt 4.18.0-479.rt7.268.el8 devel kernel-rt-devel-4.18.0-479.rt7.268.el8
        kernel-rt kernel-rt-debug 4.18.0-479.rt7.268.el8 devel kernel-rt-debug-devel-4.18.0-479.rt7.268.el8
        kernel kernel-64k 5.14.0-291.el9 devel kernel-64k-devel-5.14.0-291.el9
        kernel kernel-64k-debug 5.14.0-291.el9 devel kernel-64k-debug-devel-5.14.0-291.el9
        kernel-automotive kernel-automotive 5.14.0-301.264.el9iv devel kernel-automotive-devel-5.14.0-301.264.el9iv
        kernel-automotive kernel-automotive-debug 5.14.0-301.264.el9iv devel kernel-automotive-debug-devel-5.14.0-301.264.el9iv
        # headers
        kernel kernel 5.14.0-291.el9 headers kernel-headers-5.14.0-291.el9
        kernel kernel-debug 5.14.0-291.el9 headers kernel-headers-5.14.0-291.el9
        kernel kernel-rt 5.14.0-291.el9 headers kernel-headers-5.14.0-291.el9
        kernel kernel-rt-debug 5.14.0-291.el9 headers kernel-headers-5.14.0-291.el9
        kernel-rt kernel-rt 4.18.0-479.rt7.268.el8 headers kernel-headers-4.18.0-479.el8
        kernel-rt kernel-rt-debug 4.18.0-479.rt7.268.el8 headers kernel-headers-4.18.0-479.el8
        kernel kernel-64k 5.14.0-291.el9 headers kernel-headers-5.14.0-291.el9
        kernel kernel-64k-debug 5.14.0-291.el9 headers kernel-headers-5.14.0-291.el9
        kernel-automotive kernel-automotive 5.14.0-301.264.el9iv headers kernel-headers-5.14.0-301.el9
        kernel-automotive kernel-automotive-debug 5.14.0-301.264.el9iv headers kernel-headers-5.14.0-301.el9
        # modules-internal
        kernel kernel 5.14.0-291.el9 modules-internal kernel-modules-internal-5.14.0-291.el9
        kernel kernel-debug 5.14.0-291.el9 modules-internal kernel-debug-modules-internal-5.14.0-291.el9
        kernel kernel-rt 5.14.0-291.el9 modules-internal kernel-rt-modules-internal-5.14.0-291.el9
        kernel kernel-rt-debug 5.14.0-291.el9 modules-internal kernel-rt-debug-modules-internal-5.14.0-291.el9
        kernel-rt kernel-rt 4.18.0-479.rt7.268.el8 modules-internal kernel-rt-modules-internal-4.18.0-479.rt7.268.el8
        kernel-rt kernel-rt-debug 4.18.0-479.rt7.268.el8 modules-internal kernel-rt-debug-modules-internal-4.18.0-479.rt7.268.el8
        kernel kernel-64k 5.14.0-291.el9 modules-internal kernel-64k-modules-internal-5.14.0-291.el9
        kernel kernel-64k-debug 5.14.0-291.el9 modules-internal kernel-64k-debug-modules-internal-5.14.0-291.el9
        kernel-automotive kernel-automotive 5.14.0-301.264.el9iv modules-internal kernel-automotive-modules-internal-5.14.0-301.264.el9iv
        kernel-automotive kernel-automotive-debug 5.14.0-301.264.el9iv modules-internal kernel-automotive-debug-modules-internal-5.14.0-301.264.el9iv
        # selftests-internal
        kernel kernel 5.14.0-291.el9 selftests-internal kernel-selftests-internal-5.14.0-291.el9
        kernel kernel-debug 5.14.0-291.el9 selftests-internal kernel-selftests-internal-5.14.0-291.el9
        kernel kernel-rt 5.14.0-291.el9 selftests-internal kernel-selftests-internal-5.14.0-291.el9
        kernel kernel-rt-debug 5.14.0-291.el9 selftests-internal kernel-selftests-internal-5.14.0-291.el9
        kernel-rt kernel-rt 4.18.0-479.rt7.268.el8 selftests-internal kernel-rt-selftests-internal-4.18.0-479.rt7.268.el8
        kernel-rt kernel-rt-debug 4.18.0-479.rt7.268.el8 selftests-internal kernel-rt-selftests-internal-4.18.0-479.rt7.268.el8
        kernel kernel-64k 5.14.0-291.el9 selftests-internal kernel-selftests-internal-5.14.0-291.el9
        kernel kernel-64k-debug 5.14.0-291.el9 selftests-internal kernel-selftests-internal-5.14.0-291.el9
        kernel-automotive kernel-automotive 5.14.0-301.264.el9iv selftests-internal kernel-automotive-selftests-internal-5.14.0-301.264.el9iv
        kernel-automotive kernel-automotive-debug 5.14.0-301.264.el9iv selftests-internal kernel-automotive-selftests-internal-5.14.0-301.264.el9iv
        # tools-libs
        kernel kernel 5.14.0-291.el9 tools-libs kernel-tools-libs-5.14.0-291.el9
        kernel kernel-debug 5.14.0-291.el9 tools-libs kernel-tools-libs-5.14.0-291.el9
        kernel kernel-rt 5.14.0-291.el9 tools-libs kernel-tools-libs-5.14.0-291.el9
        kernel kernel-rt-debug 5.14.0-291.el9 tools-libs kernel-tools-libs-5.14.0-291.el9
        kernel-rt kernel-rt 4.18.0-479.rt7.268.el8 tools-libs kernel-tools-libs-4.18.0-479.el8
        kernel-rt kernel-rt-debug 4.18.0-479.rt7.268.el8 tools-libs kernel-tools-libs-4.18.0-479.el8
        kernel kernel-64k 5.14.0-291.el9 tools-libs kernel-tools-libs-5.14.0-291.el9
        kernel kernel-64k-debug 5.14.0-291.el9 tools-libs kernel-tools-libs-5.14.0-291.el9
        kernel-automotive kernel-automotive 5.14.0-301.264.el9iv tools-libs kernel-tools-libs-5.14.0-301.el9
        kernel-automotive kernel-automotive-debug 5.14.0-301.264.el9iv tools-libs kernel-tools-libs-5.14.0-301.el9
        # debuginfo-common
        kernel kernel 5.14.0-291.el9 debuginfo-common kernel-debuginfo-common-5.14.0-291.el9
        kernel kernel-debug 5.14.0-291.el9 debuginfo-common kernel-debuginfo-common-5.14.0-291.el9
        kernel kernel-rt 5.14.0-291.el9 debuginfo-common kernel-debuginfo-common-5.14.0-291.el9
        kernel kernel-rt-debug 5.14.0-291.el9 debuginfo-common kernel-debuginfo-common-5.14.0-291.el9
        kernel-rt kernel-rt 4.18.0-479.rt7.268.el8 debuginfo-common kernel-rt-debuginfo-common-4.18.0-479.rt7.268.el8
        kernel-rt kernel-rt-debug 4.18.0-479.rt7.268.el8 debuginfo-common kernel-rt-debuginfo-common-4.18.0-479.rt7.268.el8
        kernel kernel-64k 5.14.0-291.el9 debuginfo-common kernel-debuginfo-common-5.14.0-291.el9
        kernel kernel-64k-debug 5.14.0-291.el9 debuginfo-common kernel-debuginfo-common-5.14.0-291.el9
        kernel-automotive kernel-automotive 5.14.0-301.264.el9iv debuginfo-common kernel-automotive-debuginfo-common-5.14.0-301.264.el9iv
        kernel-automotive kernel-automotive-debug 5.14.0-301.264.el9iv debuginfo-common kernel-automotive-debuginfo-common-5.14.0-301.264.el9iv
    End
    Mock K_GetRunningKernelRpmName
        echo "$KERNEL_NAME"
    End
    Mock K_GetRunningKernelSrpmName
        echo "$KERNEL_SRPM_NAME"
    End
    Mock K_GetRunningKernelRpmVersionRelease
        echo "$KERNEL_VR"
    End
    It "can get $2 sub package nvr for $4"
        export KERNEL_SRPM_NAME="$1"
        export KERNEL_NAME="$2"
        export KERNEL_VR="$3"
        export KERNEL_SUBPKG="$4"
        export EXPECTED_OUTPUT="$5"
        When call K_GetRunningKernelRpmSubPackageNVR "$KERNEL_SUBPKG"
        The first line should equal "${EXPECTED_OUTPUT}"
        The status should be success
    End
End

Describe 'kernel-include: K_GetRunningKernelRpmSubPackageNVR missing parameter'
    It "fails if sub-package name is not provided"
        When call K_GetRunningKernelRpmSubPackageNVR
        The first line should equal "FAIL: missing sub-package name parameter"
        The status should be failure
    End
End
