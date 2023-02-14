#!/bin/bash

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 2036172 - [RHEL 9 Beta] The crash command terminates (SIGABRT) while checking the source code with the "l" command of GDB
# Fixed in RHEL-9.0.0 crash-8.0.0-6.el9.
RegCrashTest(){
    cat <<EOF > "bz2036172_crash_reg.cmd"
l panic
exit
EOF

    crash -i bz2036172_crash_reg.cmd > bz2036172_crash_reg.log

    RhtsSubmit "$(pwd)/bz2036172_crash_reg.cmd"
    RhtsSubmit "$(pwd)/bz2036172_crash_reg.log"

    ValidateCrashOutput "$(pwd)/bz2036172_crash_reg.log"

    # Show detailed information about crash that core dumps captured in the journal
    # if test fail with 'l panic' on crash,it will terminates and print 'Aborted (core dumped)' in console
    # or show 'Signal: 6 (ABRT)' info in below command.
    LogRun "coredumpctl info crash > bz2036172_core_dump_info.log"

    if [ -s bz2036172_core_dump_info.log ];then
        RhtsSubmit "$(pwd)/bz2036172_core_dump_info.log"
        Error "Captured core dumps,please check it."
    fi
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" RegCrashTest
