#!/bin/bash
eval "$(shellspec - -c) exit 1"

Mock rlPhaseStartSetup
    echo "rlPhaseStartSetup"
End

Mock rlCheckRpm
    echo "rlCheckRpm"
End

Mock rlShowPackageVersion
    echo "rlShowPackageVersion $*"
End

Mock rlRun
    echo "rlRun $*"
End

Mock rlAssertGrep
    echo "rlAssertGrep \"${1}\" ${2}"
    if grep "$1" "${2}"; then
        echo "PASS: rlAssertGrep \"${1}\" ${2}"
    else
        echo "FAIL: rlAssertGrep \"${1}\" ${2}"
    fi
End

Mock rlAssertNotGrep
    echo "rlAssertNotGrep \"${1}\" ${2}"
    if grep "$1" "${2}"; then
        echo "FAIL: rlAssertNotGrep \"${1}\" ${2}"
    else
        echo "PASS: rlAssertNotGrep \"${1}\" ${2}"
    fi
End

Describe 'misc/secureboot/pesign'
    It "can pass when kernel signed"
    cat <<EOF > pesign-log
certificate address is 0x7fdfb4038208
Content was not encrypted.
Content is detached; signature cannot be verified.
The signer's common name is Red Hat Secure Boot Signing 501
The signer's email address is secalert@redhat.com
Signing time: Fri Mar 28, 2025
There were certs or crls included.
EOF
        When run script misc/secureboot/pesign/runtest.sh
        The stdout should include "PASS: rlAssertGrep \"Red Hat\|Fedora\|CentOS\" pesign-signer"
        The stdout should include "PASS: rlAssertNotGrep \"Red Hat Test Certificate\" pesign-signer"
        The stdout should include "PASS: rlAssertNotGrep \"No signatures found\" pesign-log"
        The status should be success
    End

    It "can fail when kernel is not signed"
        cat <<EOF > pesign-log
certificate address is 0x7f297cc3a208
Content was not encrypted.
Content is detached; signature cannot be verified.
The signer's common name is Red Hat Test Certificate
No signer email address.
Signing time: Wed Apr 02, 2025
There were certs or crls included.
EOF
        When run script misc/secureboot/pesign/runtest.sh
        The stdout should include "PASS: rlAssertGrep \"Red Hat\|Fedora\|CentOS\" pesign-signer"
        The stdout should include "FAIL: rlAssertNotGrep \"Red Hat Test Certificate\" pesign-signer"
        The stdout should include "PASS: rlAssertNotGrep \"No signatures found\" pesign-log"
        The status should be success
    End
End
