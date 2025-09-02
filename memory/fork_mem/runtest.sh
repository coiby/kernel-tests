#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Memory/fork_mem Test
#   Author: Rachel Sibley <rasibley@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 3.
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
. ../../cki_lib/libcki.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
  rlPhaseStartSetup
    # Install avocado framework
    # Forcing version to keep it stable
    pip3 install avocado-framework==105.0
    if [ $? -ne 0 ]; then
      rlLog "Unable to install avocado framework, aborting test"
      rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
      exit 0
    fi

    echo "Disable avocado framework beaker plugin"
    cfg=~/.config/avocado/avocado.conf
    if test -d ~/.config/avocado/; then
        mv -f ~/.config/avocado/ ~/.config/avocado.restore && req_restore=1
    fi
    mkdir -p ~/.config/avocado/
    touch $cfg
    echo "[plugins]" > $cfg
    echo "disable = ['result_events.beaker']" >> $cfg
  rlPhaseEnd

  rlPhaseStartSetup
    # Clone avocado-framework-test repo"
    rlRun -l "git clone https://github.com/avocado-framework-tests/avocado-misc-tests.git"
    if [ $? -ne 0 ]; then
      rlLog "Unable to clone avocado-framework-tests, aborting test"
      rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
      exit 0
    fi
  rlPhaseEnd

  rlPhaseStartTest
    # Run fork_mem.py with timeout to make sure the test exit gracefully. If
    # there is a timeout, it also exits 0 because it seems reasonable to
    # expect a timeout exit code in machines with large RAM
    rlRun -l "avocado run avocado-misc-tests/memory/fork_mem.py --job-timeout 15m" "0,8"
    rstrnt-report-log -l /root/avocado/job-results/latest/job.log
    if [ "$req_restore" = 1 ]; then
        mv -f ~/.config/avocado.restore  ~/.config/avocado
    else
        rm -fr ~/.config/avocado
    fi
  rlPhaseEnd
rlJournalEnd

# Print the test report
rlJournalPrintText
