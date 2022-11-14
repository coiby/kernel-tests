#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/ipmitool/Sanity/smoke-test
#   Description: IPMItool smoke test
#   Author: Rachel Sibley <rasibley@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
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
. /usr/share/beakerlib/beakerlib.sh || exit 1

# RHEL7 and older use python from $PATH
# NOTE: one should install rh-python38 or newer from RHSCL
# RHEL8 and newer use /usr/libexec/platform-python (which is not in $PATH)
PYTHON=python
if grep -q "release 8" /etc/redhat-release ; then
    PYTHON=/usr/libexec/platform-python
fi
export PYTHON

rlJournalStart
    rlPhaseStartSetup
    # Exit if not ipmi compatible
    if [[ $(uname -m) != "ppc64le" ]]; then
        rlRun -l "dmidecode --type 38 > /tmp/dmidecode.log"
        if grep -i ipmi /tmp/dmidecode.log ; then
            rlPass "Moving on, host is ipmi compatible"
        else
            rlLog "Exiting, host is not ipmi compatible"
            rstrnt-report-result "$TEST" SKIP
            exit
        fi
    fi

    # Make compatible for python2/python3
    if grep -q "release 7" /etc/redhat-release ; then
        if ! rpm -qa | grep -q rh-python3 ; then
            cat > /etc/yum.repos.d/rhscl3.repo <<EOF
[rhscl3]
name=rhscl3
baseurl=http://download.devel.redhat.com/released/RHSCL/3.8/RHEL-7/Server/x86_64/os/
enabled=1
gpgcheck=0
EOF
            yum install -y rh-python38{,-pip}
        fi

        . scl_source enable rh-python38

        # fallback if RHSCL failed
        if ! command -v pip >/dev/null 2>&1 ; then
            rlLog "RHSCL failed. Go on with pip installation from https://bootstrap.pypa.io."
            rlRun -l "curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip.py"
            rlRun -l "$PYTHON get-pip.py"
            rlRun -l "pip install --user future"
        fi
    fi
    rlPhaseEnd

    rlPhaseStartTest
        # Run the main test
        rlRun -l "$PYTHON main.py"
    rlPhaseEnd
rlJournalEnd

# Print the test report
rlJournalPrintText
