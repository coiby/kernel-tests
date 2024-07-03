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
}

runtest
