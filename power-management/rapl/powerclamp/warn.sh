#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

warn_file="warn.tmp"

lines="$(wc -l "$warn_file" |sed 's/^\([0-9]*\).*/\1/')"

rlPhaseStart WARN ""
 rlAssertEquals "Warnings occured during test." "$lines" 0
rlPhaseEnd

