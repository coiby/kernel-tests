#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1939696 - function pointers that return pointer to struct fails to print
#               member offset
# Fixed in RHEL-8.5 crash-7.3.0-2.el8
analyse()
{
    CheckSkipTest crash 7.3.0-2 && return

    # Check command output of this session.
    local cmd="reg-crash.cmd"
    local output="reg-crash.out"

    # use 'struct device -ox' to check
    cat <<EOF >"$cmd"
struct device -ox | grep '(\*'
exit
EOF
    crash -i $cmd | tee $output
    RhtsSubmit "$(pwd)/$cmd"
    RhtsSubmit "$(pwd)/$output"

    #   [0x308] void (*release)(struct device *);
    grep -o '\[.*\].*([^*()]*\*[^()]*)([^()]*).*;' $output || {
        Error "regression bug: cannot print function pointer correctly"
    }

    ValidateCrashOutput "$(pwd)/$output"
}

#+---------------------------+

MultihostStage "$(basename ${0%.*})" analyse