#!/bin/bash
eval "$(shellspec - -c) exit 1"

Mock cat
    if [[ "$1" == "/sys/module/sd_mod/parameters/probe" ]]; then
        echo "sync"
        exit 0
    fi
    if [[ "$1" == "num.txt" ]]; then
        echo 0
        exit 0
    fi
    # default just peint command
    echo cat "$@"
End

Mock rhts-reboot
    echo "rhts-reboot"
End

Mock grubby
    if [[ "$1" == "--args='sd_mod.probe=sync' --update-kernel=ALL" ]]; then
        echo 0
        exit 0
    fi
    echo grubby "$@"
End

Describe 'run_test'
    Include storage/block/bz2140017_sd_mod_sync/runtest.sh
    Mock compare_two_text
        echo "compare_two_text"
    End
    It 'run_test'
        cat /sys/module/sd_mod/parameters/probe
        When call run_test
        The line 1 should include 'rlRun cat /sys/module/sd_mod/parameters/probe'
        The line 2 should include 'rlRun echo 0 > num.txt'
        The line 3 should include 'rlRun (cd /dev/disk/by-path && ls -l | grep /s)'
        The line 4 should include 'rlRun echo "1" > num.txt'
        The line 5 should include 'compare_two_text'
        The line 6 should include 'rhts-reboot'
        The status should be success
    End
End
