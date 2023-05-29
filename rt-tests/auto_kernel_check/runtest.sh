#!/bin/bash

# Enable TMT testing for RHIVOS
. ../../automotive/include/rhivos.sh || exit 1
: ${OUTPUTFILE:=runtest.log}

export TEST="rt-tests/auto_kernel_check"

function runtest() {
    # This function checks automotive kernel is running
    declare kernel_name=$(rpm -q --queryformat '%{name}\n' -qf "/boot/config-$(uname -r)" | sed 's/-core//')
    declare kernel_ver_rel=$(rpm -q --queryformat '%{version}-%{release}\n' -qf "/boot/config-$(uname -r)")
    echo "Current kernel name: $kernel_name-$kernel_ver_rel" | tee -a $OUTPUTFILE

    if [[ $kernel_name =~ kernel-automotive ]]; then
        rstrnt-report-result "kernel-automotive check" "PASS" 0
    else
        rstrnt-report-result "kernel-automotive check" "FAIL" 1
    fi
}

runtest

exit 0
