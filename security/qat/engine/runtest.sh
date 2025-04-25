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

		# Configure QAT to sym:asym encryption mode
		rlRun "python3 qat -c -m 1" 0 "Turning QAT mode to sym:asym"
	fi
rlPhaseEnd

rlPhaseStart FAIL "QATengine: qat_hw tests"
	if rlIsRHEL "<10"; then
		rlRun "openssl engine -t -c -v qatengine" 0 "Checking QATengine functionality"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 72 rsa2048" 0 "Testing RSA 2k"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 36 ecdh" 0 "Testing ECDH compute key"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 128 -multi 2 -evp aes-128-cbc-hmac-sha1" 0 "Testing aes-128-cbc-hmac-sha1 chained cipher"
		rlRun "openssl speed -engine qatengine -elapsed des" 0 "Testing DES"
		rlRun "openssl speed -engine qatengine -elapsed rand" 0 "Testing RAND"
	else
		rlRun "openssl list -providers -provider qatprovider" 0 "Checking QATprovider (>RHEL10 engine) functionality"
		rlRun "openssl speed -provider qatprovider -elapsed -async_jobs 72 rsa2048" 0 "Testing RSA 2k"
		rlRun "openssl speed -provider qatprovider -elapsed -async_jobs 36 ecdh" 0 "Testing ECDH compute key"
		rlRun "openssl speed -provider qatprovider -elapsed -async_jobs 128 -multi 2 -evp aes-128-cbc-hmac-sha1" 0 "Testing aes-128-cbc-hmac-sha1 chained cipher"
		rlRun "openssl speed -provider qatprovider -elapsed des" 0 "Testing DES"
		rlRun "openssl speed -provider qatprovider -elapsed rand" 0 "Testing RAND"
	fi
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "systemctl stop qat"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
