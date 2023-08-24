#!/bin/bash
# vim: set dictionary=/usr/share/rhts-library/dictionary.vim cpt=.,w,b,u,t,i,k:
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Author: Michal Nowak <mnowak@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright © 2009 Red Hat, Inc. All rights reserved.
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
#
# Include libraries
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../cki_lib/libcki.sh || exit 1

PACKAGE="pciutils"
PCI_IDS="/usr/share/hwdata/pci.ids"
PREFIX=

rlJournalStart
    rlPhaseStartSetup Setup
        rlAssertRpm ${PACKAGE}
        if stat /run/ostree-booted > /dev/null 2>&1; then # Detecting automotive build using ostree
            rlLog "Automotive build with ostree detected. Using local pciutils build."
            rpm-ostree install --assumeyes --apply-live --idempotent --allow-inactive gcc make
            git clone https://github.com/pciutils/pciutils
            cd pciutils || exit 1
            PREFIX="/opt/pciutils/"
            PCI_IDS="${PREFIX}share/pci.ids"
            rlLog "Build and install to ${PREFIX}"
            make PREFIX=${PREFIX} install
            cd ../
            rlLog "Remove source git repository"
            rlRun "rm -rf pciutils/"
        else
            rlFileBackup ${PCI_IDS}
        fi
    rlPhaseEnd

    rlPhaseStartTest Testing
        rlRun "lspci > lspci.old"
        cat lspci.old
        if stat /run/ostree-booted > /dev/null 2>&1; then # Detecting automotive build using ostree
            rlLog "Running local build of update-pciids"
            rlRun "${PREFIX}sbin/update-pciids" 0 "Successfully ran pciids update"
        else
            rlRun "update-pciids" 0 "Successfully ran pciids update"
        fi
        rlRun "lspci > lspci.new"
        cat lspci.new
        diff -pruN lspci.old lspci.new
    rlPhaseEnd

    rlPhaseStartCleanup Cleanup
        rlBundleLogs "$PACKAGE-outputs" lspci.old lspci.new $PCI_IDS
        if stat /run/ostree-booted > /dev/null 2>&1; then # Detecting automotive build using ostree
            rm -rf $PREFIX
        else
            rlFileRestore
        fi
        rm lspci.old lspci.new
    rlPhaseEnd
    rlJournalPrintText
rlJournalEnd
