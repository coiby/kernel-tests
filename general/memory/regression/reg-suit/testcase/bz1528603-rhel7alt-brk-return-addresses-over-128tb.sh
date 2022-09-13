#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 1528603
#   Description: Check that kernel never gives out virtual memory addresses 
#                above the 128 TeraByte boundary.
#   Author: David McDougall <dmcdouga@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Since this is an intermittent issue, run the reproducer this many times.
ATTEMPTS=1000

# Kernel outputs this message when it refuses to allocate memory above the 128
# TeraByte boundary.
SUCCESS="Cannot allocate memory"

# Reproducer prints this message when it writes to a virtual memory address
# which is above the 128 TeraByte boundary.
FAILURE="probing at 0x"

LINKER=/lib64/ld64.so.2

function bz1528603()
{
    if ! [ -e $LINKER ]; then
        rlLogWarning "Linker $LINKER not found, skipping $FUNCNAME."
        return
    fi
    if ! rlRun "gcc -o $DIR_BIN/$FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
        rlLogError "Can't build test binary"
        return
    fi

    COMMAND="$LINKER $DIR_BIN/$FUNCNAME"
    # rlRun flag '-s' copies stdout & stderr to file $rlRun_LOG
    rlRun -s "for i in \$(seq 1 $ATTEMPTS); do $COMMAND ; done" 1
    rlRun "NUM_SUCCESS=\`grep \"$SUCCESS\" $rlRun_LOG | wc -l\`"
    rlAssertEquals "Check that all attempts succeded." $NUM_SUCCESS $ATTEMPTS
    rlAssertNotGrep "$FAILURE" $rlRun_LOG
    rlRun "rm $rlRun_LOG"
    rlRun "rm $DIR_BIN/$FUNCNAME"
}
