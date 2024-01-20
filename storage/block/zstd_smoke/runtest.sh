#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

FILE=$(readlink -f $BASH_SOURCE)
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)

# TEST is required for beakerlib tests
TEST=${RSTRNT_TASKNAME}

# Include enviroment and libraries
source $CDIR/../../../cki_lib/libcki.sh || exit 1

PACKAGE="zstd"

function run_test()
{
        rlLog "check all commands"
        rlRun "zstd -h" 0
        rlRun "zstdmt -h" 0
        rlRun "unzstd -h" 0
        rlRun "zstdcat -h" 0

        rlLog "basic compression"
        rlRun "echo -e  '1\n2\n3\n4\n' > test_zstd" 0
        rlRun "zstd test_zstd" 0 "basic compression"
        rlRun "mv test_zstd test_zstd_original"
        rlRun "zstd -d test_zstd.zst" 0 "basic decompression"
        rlRun "diff test_zstd test_zstd_original" 0

        rlLog "bigger file compression"
        rlRun "dd if=/dev/zero of=large_file bs=1M count=500" 0
        rlRun "zstd large_file" 0
        rlRun "mv large_file large_file_original"
        rlRun "zstd -d large_file.zst"
        rlRun "diff large_file large_file_original"

        rlLog "other features"
        rlRun "zstd -t test_zstd.zst" 0 "Test zst file"
        rlRun -s "zstd -d --stdout test_zstd.zst" 0 "Decompress file on stdout"
	# shellcheck disable=SC2154
        rlRun "diff test_zstd_original $rlRun_LOG" 0
        rlRun "zstd -d -o test_output test_zstd.zst" 0 "Decompres file into test_output"
        rlRun "diff test_zstd_original test_output" 0
        rlRun "zstd --compress --rm test_zstd_original" 0 "Remove original file"
        rlRun "[ ! -f test_zstd_original ] && [ -f test_zstd_original.zst ]" 0 "Check file existance"
}

function check_log()
{
        rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
}

rlJournalStart
    rlPhaseStartSetup
        rlRun "dmesg -C"
        rlRun "uname -a"
        rlLog "$0"
        rlRun "rpm -q zstd || yum install -y zstd"
        rlAssertRpm $PACKAGE
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
	# shellcheck disable=SC2154
        rlRun "pushd $TmpDir"
    rlPhaseEnd

    rlPhaseStartTest
        run_test
        check_log
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
