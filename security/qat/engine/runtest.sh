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
	if ! [ -e /var/tmp/qat-reboot ]; then
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
		elif ls /lib/firmware/qat_4*.bin > /dev/null 2>%1; then
			echo "QAT firmware is active"
		else
			# Download the firmware packages if they are not present on the machine
			rlRun "wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_4xxx.bin"
			rlRun "wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_4xxx_mmp.bin"
			rlRun "mv qat_4xxx.bin /lib/firmware"
			rlRun "mv qat_4xxx_mmp.bin /lib/firmware"
		fi

		# Set reboot flag, we want it up if all of the previous steps
		# and the reboot have already happened. For the sake of the
		# other qat tests which might be in the test plan.
		rlRun "touch /var/tmp/qat-reboot"
		# Reboot to activate the firmware (Beaker safe)
		rlRun "rstrnt-reboot"
	else
		rlLogInfo "The distro release is $(rlGetDistroRelease)"
		rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
		rlLogInfo "selinux is "$(getenforce)
		rlRun "systemctl start qat"
		rlRun "pip install prettytable"
		rlRun "python3 qat -c -m 1" 0 "Turning QAT mode to sym:asym"
	fi
rlPhaseEnd

# Setup for qat_sw tests
rlPhaseStartSetup
	#rlRun "git clone https://github.com/intel/intel-ipsec-mb.git"
	#rlRun "cd intel-ipsec-mb"
	#rlRun "git checkout v1.3"
	#rlRun "make -j$(nproc)"
	#rlRun "sudo make install NOLDCONFIG=y"
	rlRun "dnf install -y https://mirror.stream.centos.org/SIGs/9-stream/extras/x86_64/extras-common/Packages/c/centos-release-isa-override-9-2.el9s.noarch.rpm" 0 "Installing override package in-script since beaker metadata can't handle links"
	rlRun "dnf install -y intel-ipsec-mb intel-ipp-crypto-mb intel-ipsec-mb-devel intel-ipp-crypto-mb-devel"

	rlRun "cd .."
	rlRun "git clone https://github.com/intel/QAT_Engine.git"
	rlRun "cd QAT_Engine/"
	rlRun "./autogen.sh"
	rlRun "./configure --enable-qat_sw"
	rlRun "make -j$(nproc) && make install"
	rlRun "cd .."
rlPhaseEnd

rlPhaseStart FAIL "QATengine: qat_hw tests"
	if rlIsRHEL "<10"; then
		rlRun "openssl engine -t -c -v qatengine" 0 "Checking QATengine functionality"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 72 rsa2048" 0 "Testing RSA 2k"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 36 ecdh" 0 "Testing ECDH compute key"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 128 -multi 2 -evp aes-128-cbc-hmac-sha1" 0 "Testing aes-128-cbc-hmac-sha1 chained cipher"
	else
		rlRun "openssl list -providers -provider qatprovider" 0 "Checking QATprovider (>RHEL10 engine) functionality"
		rlRun "openssl speed -provider qatprovider -elapsed -async_jobs 72 rsa2048" 0 "Testing RSA 2k"
		rlRun "openssl speed -provider qatprovider -elapsed -async_jobs 36 ecdh" 0 "Testing ECDH compute key"
		rlRun "openssl speed -provider qatprovider -elapsed -async_jobs 128 -multi 2 -evp aes-128-cbc-hmac-sha1" 0 "Testing aes-128-cbc-hmac-sha1 chained cipher"
	fi
rlPhaseEnd

rlPhaseStart FAIL "QATengine: qat_sw tests"
	if rlIsRHEL "<10"; then
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 8 rsa2048" 0 "Testing RSA 2k"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 8 ecdhx25519" 0 "Testing ECDH X25519"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 8 ecdhp256" 0 "Testing ECDH P-256"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 8 ecdsap256" 0 "Testing ECDSA P-256"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 8 ecdhp384" 0 "Testing ECDH P-384"
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 8 ecdsap384" 0 "Testing ECDSA P-384"
		rlRun "openssl speed -engine qatengine -elapsed -evp aes-128-gcm" 0 "Testing AES-128-GCM"
		rlRun "openssl speed -engine qatengine -elapsed -evp aes-192-gcm" 0 "Testing AES-192-GCM"
		rlRun "openssl speed -engine qatengine -elapsed -evp aes-256-gcm" 0 "Testing AES-256-GCM"
	else
	fi
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "systemctl stop qat"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
