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

FILE=$(readlink -f ${BASH_SOURCE[0]})
CDIR=$(dirname $FILE)

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
# Source the Intel QAT configuration script
. ${CDIR}/../include/lib.sh

rlJournalStart

rlPhaseStartSetup
	# Start setup, including reboot
	if ! ls /lib/firmware/qat_4*.bin > /dev/null 2>%1 || ! grubby --info=ALL | grep "intel_iommu=on sm_on"; then
		# Set kernel boot parameters for firmware
		rlRun "grubby --update-kernel=ALL --args=\"intel_iommu=on sm_on\""

		# Decompress the qat_4xxx firmware and reboot
		if ls /lib/firmware/qat_4*.bin.xz > /dev/null 2>&1; then
			rlRun "unxz /lib/firmware/qat_4*.bin.xz"
		elif ls /lib/firmware/qat_4*.bin > /dev/null 2>%1; then
			rlLogInfo "Firmware is already set up"
		fi

		# Install necessary firmware if it's not present
		if ! ls /lib/firmware/qat_4xxx*.bin > /dev/null 2>&1; then
			# Download the 4xxx firmware packages if they are not present on the machine
			rlRun "wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_4xxx.bin"
			rlRun "wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_4xxx_mmp.bin"
			rlRun "mv qat_4xxx.bin /lib/firmware"
			rlRun "mv qat_4xxx_mmp.bin /lib/firmware"
		fi
		if ! ls /lib/firmware/qat_402xx*.bin > /dev/null 2>&1; then
			# Download the 402xx firmware packages if they are not present on the machine
			rlRun "wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_402xx.bin"
			rlRun "wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_402xx_mmp.bin"
			rlRun "mv qat_402xx.bin /lib/firmware"
			rlRun "mv qat_402xx_mmp.bin /lib/firmware"
		fi

		# Reboot to activate the firmware (Beaker safe)
		rlRun "rstrnt-reboot"
	else
		# Get libzstd.a from source
		rlRun "git clone https://github.com/facebook/zstd.git"
		rlRun "cd zstd"
		rlRun "make -j$(nproc) && make install"
		rlRun "cd .."

		# Start the QAT service
		rlLogInfo "The distro release is $(rlGetDistroRelease)"
		rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
		rlLogInfo "selinux is "$(getenforce)
		rlRun "systemctl start qat"

		# Get 6.14 kernel for raw data testing
		rlRun "wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.14.tar.xz"
		rlRun "tar -xf linux-6.14.tar.xz"

		# Configure QAT to dc (de)compression mode
		rlRun "pip install prettytable"
		rlRun "run_qat \"-c -m 2\"" 0 "Turning QAT mode to dc"
	fi
rlPhaseEnd

rlPhaseStart FAIL "QATzip: qzip (de)compression of individual file"
	rlLogInfo $(rpm -q qatzip)
	rlRun "cp linux-6.14/MAINTAINERS /tmp/data" 0 "preparing data"
	cp /tmp/data /tmp/in
	rlRun "qzip /tmp/in" 0 "QAT zip"
	rlRun "qzip -d /tmp/in.gz" 0  "QAT unzip"
	rlRun "diff /tmp/data /tmp/in" 0 "Comparing decompressed file with original"
rlPhaseEnd

rlPhaseStart FAIL "QATzip: qzip multiple files"
	rlRun "qzip -k -O 7z linux-6.14/MAINTAINERS linux-6.14/CREDITS linux-6.14/README -o kernel_docs.7z"
	rlRun "qzip -k -d kernel_docs.7z"
	rlRun "ls MAINTAINERS CREDITS README > /dev/null"
rlPhaseEnd

rlPhaseStart FAIL "QATzip: qzip multiple dirs"
	rlRun "qzip -k -O 7z linux-6.14/drivers/crypto/intel/qat/qat_4xxx/ linux-6.14/drivers/crypto/intel/qat/qat_420xx/ linux-6.14/drivers/crypto/intel/qat/qat_c3xxx/ -o multi_qat.7z"
	rlRun "qzip -k -d multi_qat.7z"
	rlRun "ls qat_420xx  qat_4xxx  qat_c3xxx > /dev/null"
rlPhaseEnd

rlPhaseStart FAIL "QATzip: Intel's qatzip-test mode 4"
	rlRun "systemctl start qat"
	rlRun "qatzip-test -m 4 -l 100 -t 8 -D comp -L 1 -B 0 -i linux-6.14/MAINTAINERS" 0 "Running eight-thread level 1 compression test 100 times with sw disabled"
	rlRun "qatzip-test -m 4 -t 8 -l 100 -B 0 -i linux-6.14/MAINTAINERS -C 65536 -b 524288 -L 1 -A deflate -O gzipext -T dynamic" 0 "Running eight-thread level 1 deflation test 100 times with 65536 hw buffer and 524288 block size (data_format=gzipext && huffman=dynamic && sw disabled)"
	rlRun "qatzip-test -m 4 -t 10 -l 100 -L 1 -B 0 -A lz4 -O lz4" 0 "Running ten-threaded level 1 lz4 test 100 times (sw disabled)"
rlPhaseEnd

rlPhaseStart FAIL "QATzip: Intel's qatzip-test mode 23"
	rlRun "systemctl start qat"
	rlRun "qatzip-test -m 23 -l 1000 -t 64 -i linux-6.14/MAINTAINERS -b 65536 -e enable -B 1" 0 "Running 64-threaded test with block size 65536 1000 times with init-engine, sw, and sensitive_mode enabled"
	rlRun "qatzip-test -m 23 -l 1000 -t 64 -i linux-6.14/MAINTAINERS -b 65536 -e enable -B 0" 0 "Running 64-threaded test with block size 65536 1000 times with init-engine and sensitive mode enabled (sw disabled)"
	rlRun "qatzip-test -m 23 -l 1000 -t 64 -i linux-6.14/MAINTAINERS -b 65536 -e disable -B 0" 0 "Running 64-threaded test with block size 65536 1000 times with init-engine and sw disabled and sensitive mode enabled"
rlPhaseEnd

rlPhaseStart FAIL "QATzip: Intel's qatzip-test mode 29"
	rlRun "systemctl start qat"
	rlRun "qatzip-test -m 4 -l 2000 -t 8 -B 0 -D decomp -L 1 -i linux-6.14/MAINTAINERS -T dynamic -C 4096 -b 4096" 0 "Running eight-threaded level 1 decompression test 2000 times with hardware buff and block size 4K (huffman=dynamic && sw disabled)"
	rlRun "qatzip-test -m 4 -l 2000 -t 8 -D comp -L 1 -i linux-6.14/MAINTAINERS -A lz4 -O lz4" 0 "Running eight-threaded level 1 compression lz4 test 200 times with async queue size 2K"
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "systemctl stop qat"
	rlRun "rm -fr MAINTAINERS CREDITS README qat_420xx qat_4xxx qat_c3xxx kernel_docs.7z linux-6.14* multi_qat.7z"
	rlRun "cd zstd && make uninstall && cd .. && rm -fr zstd"
	rlRun "rm -fr QATzip"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
