#!/bin/bash

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

$@
retval="$?"

rlPhaseStart WARN "Unable to test."
 rlAssertEquals "" $retval 255
rlPhaseEnd

exit "$retval"
