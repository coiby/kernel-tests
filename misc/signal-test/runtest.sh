#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of misc/signal-test
#   Description: Test the default behavior of signals
#   Author: Yumei Huang <yuhuang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup "Preparing system signals"
        rlRun "gcc -o signal_test signal.c"
        rlAssertExists "signal_test"
    rlPhaseEnd

    rlPhaseStartTest "Verify System Signals Against Man Page"
        sys_signals=$(kill -l | tr ' ' '\n' | grep '^SIG' | awk '{print $1}')
        sig_count=$(echo "$sys_signals" | wc -w)
        rlAssertEquals "Should equal to 62 signals" 62 "$sig_count"
        man_signals=$(man 7 signal | awk -v sys_signals="$sys_signals" '
        BEGIN { in_table = 0; after_header = 0 }
        # Find start of signal table
        /Signal      Standard   Action   Comment/ { in_table = 1; next }
        /────────────────────/ { if (in_table) after_header = 1; next }
        /The signals SIGKILL and SIGSTOP/ { in_table = 0 }

        # Process signal lines
        in_table && after_header && /^\s{1,}SIG/ {
            if (index(sys_signals, $1) > 0)
                printf("%s %s\n", $1, $3)
        }
        ')
        rlRun "echo -e '$man_signals' | ./signal_test"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "pkill -9 -f 'signal_test' || true"
        rlRun "rm -f signal_test"
    rlPhaseEnd

    rlJournalPrintText
rlJournalEnd
