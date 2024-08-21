#!/bin/bash

# Source Kdump tests common functions.
. ../include/runtest.sh

# RHEL-17443 - [RHEL 9] [FJ9.3 Bug]: [REG] The values of some variables in module cannot be referenced by crash
#   Fixed in RHEL-9.5.0:crash-8.0.5-1.el9 (and 9.0z/9.2z/9.4z)

RegTest(){
    _mod_name="reg17443"
    LogRun "rm -rf $_mod_name/"
    LogRun "cp testcases/$_mod_name.c ./"
    LogRun "cp testcases/Makefile.$_mod_name ./"
    MakeModule "$_mod_name"
    LogRun "insmod $_mod_name/$_mod_name.ko" || MajorError "Unable to load $_mod_name.ko."
    LogRun "lsmod | grep $_mod_name"

    cat <<EOF > "$_mod_name.cmd"
mod -s $_mod_name $_mod_name/$_mod_name.ko
p var_static
p var_non_static
exit
EOF

    crash -i $_mod_name.cmd > $_mod_name.log

    RhtsSubmit "$(pwd)/$_mod_name.cmd"
    RhtsSubmit "$(pwd)/$_mod_name.log"

    ValidateCrashOutput "$(pwd)/$_mod_name.log"
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" RegTest
