#!/bin/bash

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 2056837 - [RHEL 9 Beta] 'sys' command displays the man page if the first argument passed to it is a crash built-in command.
# Fixed in RHEL-9.1.0 crash-8.0.1-2.el9.
if $IS_RHEL9; then
    CheckSkipTest crash 8.0.1-2 && Report
elif $IS_RHEL8 || $IS_RHEL7; then
    CheckSkipTest crash 7.3.2-2 && Report
fi

RegTest(){
    # Bug 2056837 - [RHEL 9 Beta] 'sys' command displays the man page if the first argument passed to it is a crash built-in command.
    # Fixed in RHEL-9.1.0 crash-8.0.1-2.el9.
    cat <<EOF > "bz2056837_crash_reg.cmd"
sys sys
sys kmem
exit
EOF

    crash -i bz2056837_crash_reg.cmd > bz2056837_crash_reg.log

    RhtsSubmit "$(pwd)/bz2056837_crash_reg.cmd"
    RhtsSubmit "$(pwd)/bz2056837_crash_reg.log"

    ValidateCrashOutput "$(pwd)/bz2056837_crash_reg.log"

    # before fix:
    # crash> sys kmem |head
    # NAME
    #   kmem - kernel memory
    # SYNOPSIS
    #   kmem [-f|-F|-c|-C|-i|-v|-V|-n|-z|-o|-h] [-p | -m member[,member]]
    #   [[-s|-S|-S=cpu[s]|-r] [slab] [-I slab[,slab]]] [-g [flags]] [[-P] address]]
    # after fix:
    # crash> sys kmem
    # Usage:
    #   sys [-c [name|number]] [-t] [-i] config
    # Enter "help sys" for details.
    num1=$(grep -c 'help sys' "$(pwd)/bz2056837_crash_reg.log")
    num2=$(grep -c 'Usage:' "$(pwd)/bz2056837_crash_reg.log")
    if [ "$num1" -ne 2 ] || [ "$num2" -ne 2 ];then
        Error "It should be display the 'Usage' message."
    fi
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" RegTest
