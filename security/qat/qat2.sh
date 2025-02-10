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
# found at https://gitlab.cee.redhat.com/vmarsik/bkrjobs 

dnf install -y beakerlib qatlib qatlib-service qatengine qatlib-tests qatzip

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

DISTRO=$(grep DISTRO /etc/motd | cut -d= -f2)
if [ -z "$DISTRO" ]
then
	DISTRO=$(cat /etc/redhat-release)
fi

rlJournalStart

#rlPhaseStartSetup
#	if ! grubby --info=DEFAULT | grep intel_iommu > /dev/null
#	then
#		rlRun "grubby --args=intel_iommu=on --update-kernel=ALL"
#		rlRun "rhts-reboot"
#	fi
#rlPhaseEnd

rlPhaseStart FAIL "Functionality"
	rlLogInfo "$DISTRO"
	rlLogInfo "kernel $(uname -r; rpm -q qatlib qatengine)"
	rlLogInfo "selinug "$(getenforce)
	rlRun "systemctl start qat"
	rlRun "cpa_sample_code"
	if rlIsRHEL "<10"; then
		rlRun "openssl speed -engine qatengine -elapsed -async_jobs 72 rsa2048"
		rlRun "openssl speed -engine qatengine -elapsed ecdhx25519"
		rlRun "openssl engine -t -c -v qatengine"
	else
		rlRun "openssl speed -provider qatprovider -elapsed -async_jobs 72 rsa2048"
		rlRun "openssl speed -provider qatprovider -elapsed ecdhx25519"
		rlRun "openssl list -providers -provider qatprovider"
	fi
rlPhaseEnd

rlPhaseStart FAIL "QATzip"
	rlLogInfo $(rpm -q qatzip)
	TMP=`mktemp`
	rlRun "dd if=/dev/random of=/tmp/data bs=1M count=1024" 0 "preparing data"
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
	ZIP_RATIO=$(echo ${GZIP_TIME}/${QZIP_TIME} | bc -l)
	UNZIP_RATIO=$(echo ${GUNZIP_TIME}/${QUNZIP_TIME} | bc -l)
	rlLogInfo "qzip/gzip speed: ${ZIP_RATIO}"
	rlLogInfo "qunzip/gunzip speed: ${UNZIP_RATIO}"
	rm ${TMP}
rlPhaseEnd

rlPhaseStart FAIL "QAT-ZSTD-Plugin"
	rlRun "./include/setup_qat_zstd_plugin.sh" 0 "setting up zstd plugin testing environment"
	rlRun "./QAT-ZSTD-Plugin/test/test dickens" 0 "compressing and decompressing dickens"
rlPhaseEnd

rlPhaseStartCleanup
#	rlRun "popd"
#	rlRun "rm -rf $GITDIR"
	rlRun "systemctl stop qat"
#	if cat /etc/default/grub | grep intel_iommu > /dev/null
#	then
#		rlRun "sed -ie 's/ intel_iommu=on//' /etc/default/grub"
#		rlRun "grub2-mkconfig -o /etc/grub2-efi.cfg"
#	fi
rlPhaseEnd

rlJournalPrintText
rlJournalEnd



