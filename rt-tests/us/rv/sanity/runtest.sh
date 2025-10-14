#!/bin/bash

# Source rt common functions
. ../../../include/lib.sh || exit 1

function runtest()
{
    if rhel_in_range 0 9.2; then
        rstrnt-report-result "rv is only supported for RHEL >= 9.3" "SKIP" 0
        exit 0
    fi


    oneliner "dnf install -y rv"

    # check rv help page
    oneliner "rv --help"

    # check rv list available monitors
    oneliner "rv list"
    ral=$(rv list | awk -F' ' '{print $1}')
    log "Available monitors: $ral"

    # check that monitors have the correct syntax
    # name, then description, then whether it is on or off
    phase_start_test check_monitor_syntax
    while read -r line
    do
        run "echo $line | grep -E '[[:alnum:]]+[ ]+[[:print:]]+\[(OFF|ON)\]'"
    done < <(rv list)
    phase_end
}

runtest
