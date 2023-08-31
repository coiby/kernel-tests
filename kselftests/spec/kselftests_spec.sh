#!/bin/bash
eval "$(shellspec - -c) exit 1"

pushd() {
    echo "pushd $*"
}

popd() {
    echo "popd $*"
}

Mock wget
    echo "wget $*"
    exit "${WGET_EXIT_CODE:=0}"
End

Mock tar
    echo "tar $*"
End

Describe 'kselftests: install_kselftests from rpms'
    export CKI_SELFTESTS_URL=""
    export BUILD_FROM_SRC=""
    export DELIVERED_TESTS=1
    Include kselftests/runtest.sh
    # They need to be mocked after the include
    Mock K_GetRunningKernelRpmName
        echo "${KERNEL_NAME}"
    End
    Mock K_GetRunningKernelRpmVersionRelease
        echo "${KERNEL_VERSION_RELEASE}"
    End
    Mock K_GetRunningKernelSrpmName
        echo "${KERNEL_SRPM_NAME}"
    End
    Mock K_IsKernelRPM
        exit 0
    End

    Parameters
        # kernel with variants
        kernel kernel 5.14.0-303.el9
        kernel-debug kernel 5.14.0-303.el9
        kernel-rt kernel 5.14.0-303.el9
        kernel-rt-debug kernel 5.14.0-303.el9
        kernel-64k kernel 5.14.0-303.el9
        kernel-64k-debug kernel 5.14.0-303.el9
        # kernels witthout variants
        kernel-rt kernel-rt 4.18.0-488.el8
        kernel-rt-debug kernel-rt 4.18.0-488.el8
    End

    It "can install with rpms $1 $2 $3"
        Mock rpm
            echo "rpm $*"
            [[ "$*" =~ "--quiet -q modules-extra".* ]] && exit 1
            [[ "$*" =~ "--quiet -q modules-internal".* ]] && exit 1
            [[ "$*" =~ "--quiet -q ${KERNEL_SRPM_NAME}-selftests-internal".* ]] && exit 1
            [[ "$*" =~ "-q ${KERNEL_SRPM_NAME}-selftests-internal".* ]] && exit 0
        End
        export pkg_mgr=dnf
        export pkg_mgr_inst_string="install -y"
        export KERNEL_NAME="$1"
        export KERNEL_SRPM_NAME="$2"
        export KERNEL_VERSION_RELEASE="$3"
        export arch=x86_64
        When call install_kselftests
        The first line should include "rpm --quiet -q ${KERNEL_NAME}-modules-extra-${KERNEL_VERSION_RELEASE}"
        The second line should equal "rlRpmDownload ${KERNEL_NAME}-modules-extra-${KERNEL_VERSION_RELEASE}.${arch}"
        The line 3 should equal "rlRun $pkg_mgr $pkg_mgr_inst_string ./${KERNEL_NAME}-modules-extra-${KERNEL_VERSION_RELEASE}.${arch}.rpm"

        The line 4 should include "rpm --quiet -q ${KERNEL_NAME}-modules-internal-${KERNEL_VERSION_RELEASE}"
        The line 5 should equal "rlRpmDownload ${KERNEL_NAME}-modules-internal-${KERNEL_VERSION_RELEASE}.${arch}"
        The line 6 should equal "rlRun $pkg_mgr $pkg_mgr_inst_string ./${KERNEL_NAME}-modules-internal-${KERNEL_VERSION_RELEASE}.${arch}.rpm"

        The line 7 should include "rpm --quiet -q ${KERNEL_SRPM_NAME}-selftests-internal-${KERNEL_VERSION_RELEASE}"
        The line 8 should equal "rlRpmDownload ${KERNEL_SRPM_NAME}-selftests-internal-${KERNEL_VERSION_RELEASE}.${arch}"
        The line 9 should equal "rlRun $pkg_mgr $pkg_mgr_inst_string ./${KERNEL_SRPM_NAME}-selftests-internal-${KERNEL_VERSION_RELEASE}.${arch}.rpm"

        The stdout should include "rlLog Delivered kselftests installed..."
        The status should be success
    End
End

Describe 'kselftests: install_kselftests - CKI_SELFTESTS_URL'
    export CKI_SELFTESTS_URL=http://www.testurl.com/kselftest.tar.gz
    Include kselftests/runtest.sh
    # It needs to be mocked after the include
    Mock K_GetRunningKernelRpmSubPackageNVR
        exit
    End
    It "can install with CKI_SELFTESTS_URL"
        When call install_kselftests
        The first line should include "/var/tmp"
        The second line should equal "wget --no-check-certificate http://www.testurl.com/kselftest.tar.gz -O kselftest.tar.gz"
        The third line should equal "tar zxf kselftest.tar.gz"
        The stdout should include "Upstream kselftests installed"
        The status should be success
    End

    It "can detect failure to download tarball with CKI_SELFTESTS_URL"
        export WGET_EXIT_CODE=1
        When call install_kselftests
        The stdout should include "Wget CKI_SELFTESTS_URL failed"
        The status should be failure
    End
End
