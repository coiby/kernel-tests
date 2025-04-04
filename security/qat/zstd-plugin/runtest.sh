#!/bin/bash

#   Copyright (c) 2018 Red Hat, Inc.
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
# may need to set kernel options intel_iommu=on,sm_on module_blacklist=idxd
#
# Original script written by Vilem Marsik <vmarsik@redhat.com>

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

# Setting up environment for qatlib, qatengine, and qatzip testing
rlPhaseStartSetup
	# Start setup, including reboot
	if ! ls /lib/firmware/qat_4*.bin > /dev/null 2>%1; then
		# Set kernel boot parameters for firmware and to reboot back
		# into test execution
		rlRun "grubby --update-kernel=ALL --args=\"intel_iommu=on sm_on\""

		# Decompress the qat_4xxx firmware and reboot
		if ls /lib/firmware/qat_4*.bin.xz > /dev/null 2>&1; then
			rlRun "unxz /lib/firmware/qat_4*.bin.xz"
		else
			# Download the firmware packages if they are not present on the machine
			rlRun "wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_4xxx.bin"
			rlRun "wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_4xxx_mmp.bin"
			rlRun "mv qat_4xxx.bin /lib/firmware"
			rlRun "mv qat_4xxx_mmp.bin /lib/firmware"
		fi

		# Reboot to activate the firmware (Beaker safe)
		rlRun "rstrnt-reboot"
	else
		# Create nullbytes test file
		rlRun "dd < /dev/zero bs=10485760 count=1 > nullbytes"

		# Run the Intel QAT configuration script
		rlRun "pip install prettytable"
		rlRun "python3 qat -c -m 2" 0 "reconfiguring QAT devices to (de)compression mode"

		# Get zstd setup files
		rlRun "git clone https://github.com/facebook/zstd.git"
		rlRun "cd zstd"
		rlRun "make -j$(nproc) && make install"
		rlRun "cd .."

		# Include qat headers in c include path
		rlRun "export C_INCLUDE_PATH=/usr/include/qat/:$C_INCLUDE_PATH"

		# Get the baseline QAT ZSTD Plugin tests
		rlRun "git clone https://github.com/intel/QAT-ZSTD-Plugin.git"
		rlRun "cd QAT-ZSTD-Plugin/test"
		rlRun "make"
		rlRun "cd fuzzing"
		rlRun "make qatseqprodfuzzer.o"
		rlRun "cd ../../.."

		# Build fuzzing targets
		rlRun "cd zstd/tests/fuzz/"
		rlRun "make corpora"
		rlRun "python3 ./fuzz.py build all --custom-seq-prod=~/QAT-ZSTD-Plugin/test/fuzzing/qatseqprodfuzzer.o --enable-fuzzer --enable-asan --enable-ubsan --cc clang --cxx clang++ --ldflags=-lqat_s"
		rlRun "cd ../../.."

		# Logging and starting qat.service
		rlLogInfo "The distro release is $(rlGetDistroRelease)"
		rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
		rlLogInfo "selinux is "$(getenforce)
		rlRun "systemctl start qat"
		rlRun "systemctl enable qat"

		# Add path to user enabled ld libs
		rlRun "export LD_LIBRARY_PATH=/usr/lib64:$LD_LIBRARY_PATH"
	fi
rlPhaseEnd

rlPhaseStart FAIL "QAT-ZSTD-Plugin: basic (de)compression test"
	rlRun "./QAT-ZSTD-Plugin/test/test nullbytes" 0 "compressing and decompressing zeroes"
rlPhaseEnd

rlPhaseStart FAIL "QAT-ZSTD-Plugin: benchmark test"
	rlRun "./QAT-ZSTD-Plugin/test/benchmark -m1 -l100 -c64K -t64 -E2 nullbytes"
rlPhaseEnd

rlPhaseStart FAIL "QAT-ZSTD-Plugin: fuzzing tests"
	rlRun "cd zstd/tests/fuzz"
	rlRun "python3 ./fuzz.py libfuzzer simple_round_trip"
	rlRun "python3 ./fuzz.py libfuzzer stream_round_trip"
	rlRun "python3 ./fuzz.py libfuzzer dictionary_round_trip"
	rlRun "python3 ./fuzz.py libfuzzer block_round_trip"
	rlRun "python3 ./fuzz.py libfuzzer decompress_dstSize_tooSmall"
	rlRun "python3 ./fuzz.py libfuzzer dictionary_decompress"
	rlRun "python3 ./fuzz.py libfuzzer dictionary_loader"
	rlRun "python3 ./fuzz.py libfuzzer dictionary_stream_round_trip"
	rlRun "python3 ./fuzz.py libfuzzer raw_dictionary_round_trip"
	rlRun "python3 ./fuzz.py libfuzzer sequence_compression_api"
	rlRun "python3 ./fuzz.py libfuzzer simple_compress"
	rlRun "cd ../../.."
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "systemctl stop qat"
	rlRun "rm -fr QAT-ZSTD-Plugin/ zstd/ nullbytes"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
