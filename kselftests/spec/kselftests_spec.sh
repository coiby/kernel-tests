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


Describe 'kselftests: install_kselftests - CKI_SELFTESTS_URL'
    export CKI_SELFTESTS_URL=http://www.testurl.com/kselftest.tar.gz
    Include kselftests/runtest.sh
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
