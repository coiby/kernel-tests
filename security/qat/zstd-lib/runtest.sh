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
		# Get libzstd.a from source
		rlRun "git clone https://github.com/facebook/zstd.git"
		rlRun "cd zstd"
		rlRun "make -j$(nproc) && make install"
		rlRun "cd .."

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
		rlLogInfo "The distro release is $(rlGetDistroRelease)"
		rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
		rlLogInfo "selinux is "$(getenforce)
		rlRun "systemctl start qat"
	fi
rlPhaseEnd

rlPhaseStartSetup
	# Run the Intel QAT configuration script
	rlRun "pip install prettytable"
	rlRun "python3 qat --config" 0 "reconfiguring QAT devices"

	# Get the baseline QAT ZSTD Plugin tests
	rlRun "git clone https://github.com/intel/QAT-ZSTD-Plugin.git"

	# Compile
	rlRun "cd QAT-ZSTD-Plugin/"
	rlRun "make test"
	rlRun "cd .."
rlPhaseEnd

rlPhaseStart FAIL "QAT-ZSTD-Plugin"
	rlRun "./QAT-ZSTD-Plugin/test/test nullbytes" 0 "compressing and decompressing zeroes"
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "systemctl stop qat"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
