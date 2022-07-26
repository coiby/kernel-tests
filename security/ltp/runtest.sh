#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
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

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        yum install autoconf \
                    automake \
                    bison \
                    elfutils-libelf-devel \
                    flex \
                    gcc \
                    git \
                    glibc-headers \
                    kernel-devel \
                    kernel-headers \
                    keyutils-libs-devel \
                    libacl-devel \
                    libcap-devel \
                    libselinux-devel \
                    libtirpc-devel \
                    lksctp-tools-devel \
                    m4 \
                    make \
                    numactl-devel \
                    openssl-devel \
                    pkgconf \
                    xfsprogs-devel \
                    -y
        rlRun "git clone https://github.com/linux-test-project/ltp.git"
        rlRun "cd ltp"
        rlRun "make -s autotools"
        rlRun "./configure > /dev/null"
        rlRun "make -s all &> /dev/null"
        rlRun "make -s install > /dev/null"
    rlPhaseEnd

    rlPhaseStartTest "cap_bounds"
        rlRun "/opt/ltp/runltp -f cap_bounds"
    rlPhaseEnd

    rlPhaseStartTest "filecaps"
        rlRun "/opt/ltp/runltp -f filecaps"
    rlPhaseEnd

    rlPhaseStartTest "prot_hsymlinks"
        rlRun "/opt/ltp/runltp -f syscalls -s prot_hsymlinks"
    rlPhaseEnd

    rlPhaseStartTest "cve"
        rlRun "/opt/ltp/runltp -f cve"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "make -s clean > /dev/null"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
