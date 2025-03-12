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
		# Set kernel boot parameters for firmware and to reboot back
		# into test execution
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
		# Get a file to test on, recommended in the QAT ZSTD Plugin repo
		rlRun "wget https://github.com/yewq/Silesia-compression-corpus/raw/refs/heads/main/dickens.bz2"
		rlLogInfo "The distro release is $(rlGetDistroRelease)"
		rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
		rlLogInfo "selinux is "$(getenforce)
		rlRun "systemctl start qat"
	fi
rlPhaseEnd

rlPhaseStart FAIL "QATzip"
	rlLogInfo $(rpm -q qatzip)
	TMP=`mktemp`
	rlRun "bunzip2 dickens.bz2 -c > /tmp/data" 0 "preparing data"
	cp /tmp/data /tmp/in
	rlRun "/bin/time -f '%e' qzip /tmp/in 2>\"$TMP\"" 0 "QAT zip"
	QZIP_TIME=$(cat "$TMP")
	rlLogInfo "Time: ${QZIP_TIME} s"
	rlRun "/bin/time -f '%e' qzip -d /tmp/in.gz 2>\"$TMP\"" 0  "QAT unzip"
	QUNZIP_TIME=$(cat "$TMP")
	rlLogInfo "Time: ${QUNZIP_TIME} s"
	rlRun "diff /tmp/data /tmp/in" 0 "Comparing decompressed file with original"
	rlRun "/bin/time -f '%e' gzip /tmp/data 2>\"$TMP\"" 0 "gzip"
	GZIP_TIME=$(cat "$TMP")
	rlLogInfo "Time: ${GZIP_TIME} s"
	rlRun "/bin/time -f '%e' gzip -d /tmp/data.gz 2>\"$TMP\"" 0 "gunzip"
	GUNZIP_TIME=$(cat "$TMP")
	rlLogInfo "Time: ${GUNZIP_TIME} s"
	ZIP_RATIO=$(echo ${QZIP_TIME}/${GZIP_TIME} | bc -l)
	UNZIP_RATIO=$(echo ${QUNZIP_TIME}/${GUNZIP_TIME} | bc -l)
	rlLogInfo "qzip/gzip speed: ${ZIP_RATIO}"
	rlLogInfo "qunzip/gunzip speed: ${UNZIP_RATIO}"
	rm ${TMP}
rlPhaseEnd

rlPhaseStartCleanup
	rlRun "systemctl stop qat"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
