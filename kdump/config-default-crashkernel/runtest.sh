#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# shellcheck source=/dev/null
. /usr/share/beakerlib/beakerlib.sh || exit 1

. ../include/tmt.sh

rlJournalStart


    rlPhaseStartTest
    if echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
        rlLog "Skip test on server side"
        rlJournalEnd
    fi

    _default_crashkernel=$(kdumpctl get-default-crashkernel)
    if grep "crashkernel=$_default_crashkernel" /proc/cmdline; then
        rlRun "kdumpctl showmem"
        rlLog "Default crashkernel set"
    elif [ "$TMT_REBOOT_COUNT" == 0 ]; then
        rlRun "kdumpctl reset-crashkernel --kernel=ALL"
        rlRun "tmt-reboot"
    else
        rlFail "Failed to set up default crashkernel"
    fi
    rlPhaseEnd

rlJournalEnd
