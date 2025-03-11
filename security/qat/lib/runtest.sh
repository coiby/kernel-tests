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
		rlRun "pip install prettytable"
		rlLogInfo "The distro release is $(rlGetDistroRelease)"
		rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
		rlLogInfo "selinux is "$(getenforce)
		rlRun "systemctl start qat"
	fi
rlPhaseEnd

rlPhaseStart FAIL "QATlib: baseline functionality verification"
	rlRun "cpa_sample_code"
rlPhaseEnd

rlPhaseStart FAIL "QATlib: sym/asym encryption operations"
	rlRun "python3 qat -c -m 1" 0 "Setting QAT mode to sym:asym"
	rlRun "algchaining_sample"
	rlRun "ccm_sample"
	rlRun "cipher_sample"
	rlRun "ec_montedwds_sample"
	rlRun "eddsa_sample"
	rlRun "gcm_sample"
	rlRun "hash_file_sample"
	rlRun "hash_sample"
	rlRun "hkdf_sample"
	rlRun "ipsec_sample"
	rlRun "prime_sample"
	rlRun "ssl_sample"
	rlRun "sym_dp_sample"
rlPhaseEnd

rlPhaseStart FAIL "QATlib: dc compression operations"
	rlRun "python3 qat -c -m 2" 0 "Setting QAT mode to dc"
	rlRun "dc_dp_sample"
	rlRun "dc_stateless_multi_op_sample"
	rlRun "dc_stateless_sample"
rlPhaseEnd

rlPhaseStart FAIL "QAT:lib: dcc operations"
	rlRun "python3 qat -c -m 7" 0 "Setting QAT mode to dcc"
	rlRun "chaining_sample"
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "systemctl stop qat"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
