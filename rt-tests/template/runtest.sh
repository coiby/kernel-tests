#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Enable TMT testing for RHIVOS
. ../../automotive/include/rhivos.sh || exit 1
: ${OUTPUTFILE:=runtest.log}

# Source rt common functions
. ../include/runtest.sh || exit 1

# Update TEST to the relative path of the test case
export TEST="rt-tests/template"

function RunTest ()
{
    echo "Test Start Time: $(date)" | tee -a $OUTPUTFILE
    cat /proc/sys/net/netfilter/nf_log/* | tee -a $OUTPUTFILE
    cat /proc/*/net/dev | tee -a $OUTPUTFILE
    echo "Test End Time: $(date)" | tee -a $OUTPUTFILE
    rstrnt-report-result $TEST "PASS" 0
}

# ---------- Start Test -------------
if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
    if ! kernel_automotive; then
        # Install standard realtime packages if kernel-rt is running, otherwise
        # SKIP this test, it's required for all rt-tests.
        rt_env_setup
    fi
    RunTest

    # Sometimes reboot is needed to cleanup residual *things* of current
    # test that may affect proceeding test(s)
    rstrnt-reboot
fi

exit 0


