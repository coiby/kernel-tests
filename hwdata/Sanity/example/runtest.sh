#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/hwdata/Sanity/example
#   Description: Example sanity script to print pci/usb device id's
#   Author: Rachel Sibley <rasibley@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Set the full test name
export TEST="/kernel/hwdata/Sanity/example"

# RHEL7 and older use python from $PATH
# RHEL8 and newer use /usr/libexec/platform-python (which is not in $PATH)
PYTHON=/usr/libexec/platform-python
if grep -q "release 7" /etc/redhat-release ; then
	PYTHON=python
fi
export PYTHON

rlJournalStart
# Exit if example.py returns a warning (BZ 1380159)
    rlPhaseStartTest
	if rlRun -l "${PYTHON} /usr/share/doc/python*-hwdata*/example.py" 0 ; then
                rlPass "Pass, example.py script returned the id's succssfully"
        else
                rlFail "Fail, example.py returned a warning"
        fi
    rlPhaseEnd

    # uninstall/install hwdata and python3-hwdata pkgs, verify pkgs insalled correctly
    rlPhaseStartTest
        rlRun -l "yum remove -y hwdata python*-hwdata"
        rlRun -l "yum install -y hwdata python*-hwdata"
        rlCheckRpm hwdata
        rlCheckRpm python-hwdata
    rlPhaseEnd

rlJournalEnd
# Print the test report
rlJournalPrintText
