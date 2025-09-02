#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/misc/self-poweroff
#   Description: Powers itself off
#   Author: Erico Nunes <ernunes@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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

# Enable TMT testing for RHIVOS
. ../../cki_lib/libcki.sh || exit 1

if ! cki_is_kernel_automotive; then
    # Include rhts environment
    . /usr/bin/rhts-environment.sh
fi

# Source the common test script helpers
. /usr/share/beakerlib/beakerlib.sh || exit 1

export TEST="misc/self-poweroff"

# This file will be created to record that this job has already run
# once. When the guest gets powered on again by the host, we don't want
# to power off repeatedly.

if cki_is_kernel_automotive; then
    STAMP_FILE=/tmp/.self-poweroff
else
    STAMP_FILE=/.self-poweroff
fi

if [ -f $STAMP_FILE ]; then
    rm $STAMP_FILE
    rstrnt-report-result "${TEST}" PASS
    exit 0
fi

touch $STAMP_FILE
sync
# Instead of using /sbin/poweroff, it is to add waiting time
# before shutdown, if shut down immediately,
# tmt cannot get the test results from the tested host
/sbin/shutdown -t +1
rstrnt-report-result "${TEST}" PASS
exit 0