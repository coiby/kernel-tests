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
		# Get a file to test on, recommended in the QAT ZSTD Plugin repo
		rlRun "wget https://github.com/yewq/Silesia-compression-corpus/raw/refs/heads/main/dickens.bz2"
		rlLogInfo "The distro release is $(rlGetDistroRelease)"
		rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
		rlLogInfo "selinux is "$(getenforce)
		rlRun "systemctl start qat"
	fi
rlPhaseEnd

rlPhaseStartSetup
	# Get all necessary includes
	rlRun "git clone https://github.com/intel/qatlib.git"
	rlRun "cd qatlib"
	rlRun "./autogen.sh" 0 "generating necessary include files"
	rlRun "./configure --enable-service" 0 "configuring include files"
	rlRun "make -j$(nproc)" 0 "making include files"
	rlRun "make install" 0 "installing necessary include files"
	rlRun "cd .."
	rlRun "dnf reinstall -y qatlib qatengine"

	# Run the Intel QAT configuration script
	rlRun "pip install prettytable"
	rlRun "python3 qat --config" 0 "reconfiguring QAT devices"

	# Get the baseline QAT ZSTD Plugin tests
	rlRun "git clone https://github.com/intel/QAT-ZSTD-Plugin.git"

	# Decompress test file
	rlRun "bunzip2 dickens.bz2"

	# Compile
	rlRun "cd QAT-ZSTD-Plugin/"
	rlRun "make test"
	rlRun "cd .."
rlPhaseEnd

rlPhaseStart FAIL "QAT-ZSTD-Plugin"
	rlRun "./QAT-ZSTD-Plugin/test/test dickens" 0 "compressing and decompressing dickens"
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "systemctl stop qat"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd



