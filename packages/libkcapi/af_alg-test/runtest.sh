#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
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

. /usr/share/beakerlib/beakerlib.sh

GIT_URL="${GIT_URL:-https://github.com/smuellerDD/libkcapi}"
GIT_REF="${GIT_REF:-fc937358e71253a6efaa3ba74885364976b040ea}"

function version_le() {
    { echo "$1"; echo "$2"; } | sort -V | tail -n 1 | grep -qx "$2"
}

function kver_ge() { version_le "$1" "$(uname -r)"; }
function kver_lt() { ! kver_ge "$1"; }
function kver_le() { version_le "$(uname -r)" "$1"; }
function kver_gt() { ! kver_le "$1"; }

function abort() {
    local msg="$1"

    if command -v rstrnt-report-result &>/dev/null; then
        rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
        exit 1
    fi
    rlDie "$msg"
}

rlJournalStart
    rlPhaseStartSetup
        if ! rlRun "git clone '$GIT_URL' libkcapi"; then
            abort "Unable to clone the libkcapi repo!"
        fi
        if ! rlRun "(cd libkcapi && git checkout $GIT_REF)"; then
            abort "Unable to checkout the requested git ref!"
        fi
        if ! rlRun "(cd libkcapi && autoreconf -i)"; then
            abort "Unable to prepare build environment!"
        fi

        # Old versions of aes_neon_bs cause some tests to fail. Fixed in:
        # https://bugzilla.redhat.com/show_bug.cgi?id=1826982
        # NOTE: This was actually fixed in 4.18.0-193.15.el8, but because of
        # stupid Z-stream kernel versioning we need to compare to -194...
        if rlIsRHEL && kver_lt 4.18.0-194; then
            rlRun "rmmod aes_neon_bs" 0-1 "Remove buggy aes_neon_bs module"
        fi
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "sed -i 's/^exec_test$/exec_test; exit \$?/' libkcapi/test/test-invocation.sh" 0 \
            "Skip the compilation and 32-bit tests"
        # NOTE: we could enable the fuzz tests with ENABLE_FUZZ_TEST=1, but
        # they take a veeeery long time to run and so far I haven't seen
        # them actually uncover a bug... Let's just keep them off for now.
        rlRun "./libkcapi/test/test-invocation.sh"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -rf libkcapi"
        rlFileSubmit "/proc/crypto" "proc-crypto.txt"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
