#!/bin/bash

function bz1733016()
{
    if [ "$(rlGetPrimaryArch)" != "x86_64" ]; then
        rlLog "Only for x86_64"
        return
    fi

    rlRun "gcc -o ${FUNCNAME} $DIR_SOURCE/${FUNCNAME}.c"
    if [ $? != "0" ]; then
        rlLogWarning "Can't build test binary"
        return
    fi

    rlRun "sysctl -w 'kernel.sem=5120 32000 32 128'"
    for i in `seq 5`; do 
        rlRun "./bz1733016 2049"
    done
}
