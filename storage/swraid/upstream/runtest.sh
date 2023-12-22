#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh

TESTS=${TESTS:-"06name"}

function infra_failure()
{
    reason="$*"
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    echo "Aborting task due to ${reason}"
    rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
    exit 1
}

function run_setup()
{
    rm -rf mdadm
    if ! rlRun "git clone git://git.kernel.org/pub/scm/utils/mdadm/mdadm.git"; then
        infra_failure "couldn't clone repo"
    fi

    rlRun "make -C mdadm everything" || infra_failure "couldn't build tests"
}

rlJournalStart
    rlPhaseStartSetup
        rlRun "uname -a"
        run_setup
    rlPhaseEnd
    read -ra tests <<< "$TESTS"
    cd mdadm || exit 1
    for test in "${tests[@]}"; do
        [ ! -f "tests/${test}" ] && continue
        rlPhaseStartTest "${test}"
            rlRun "dmesg -C"
            rlRun "./test --logdir=./logs --tests=${test}"
        rlPhaseEnd
    done
    for log in ./logs/*; do
        rhts-submit-log -l "${log}"
    done
rlJournalPrintText
rlJournalEnd
