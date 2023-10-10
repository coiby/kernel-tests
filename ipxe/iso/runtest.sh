#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

rlPhaseStartSetup
rlRun "systemctl start httpd"
rlRun "systemctl start libvirtd"

TEST_KERNEL_VERSION=$(curl http://download.devel.redhat.com/qa/rhts/lookaside/ipxe-iso-test/version.txt)

rlRun "curl http://download.devel.redhat.com/qa/rhts/lookaside/ipxe-iso-test/vmlinuz    >/var/www/html/vmlinuz"
rlRun "curl http://download.devel.redhat.com/qa/rhts/lookaside/ipxe-iso-test/initrd.img >/var/www/html/initrd.img"

cat >/var/www/html/boot.txt <<EOF
#!ipxe

kernel http://$(hostname)/vmlinuz console=ttyS0 debug rd.shell rd.retry=0
initrd http://$(hostname)/initrd.img
boot
EOF

export TEST_PING_CMD=0
# only enable ping cmd test in known supported versions
vr=$(rpm -q --qf '%{version}-%{release}' ipxe-bootimgs)
if rlTestVersion "$vr" ">=" "20181214-7.git133f4c47"
then
	export TEST_PING_CMD=1
fi

rlRun "cat /var/www/html/boot.txt"
rlRun "chmod a+r /var/www/html/*"

rlRun "sed -i \"s/KERNEL_VERSION/$TEST_KERNEL_VERSION/\" ipxe-script.exp"
rlRun "sed -i \"s/HYPERVISOR_HOSTNAME/$(hostname)/\" ipxe-script.exp"
rlPhaseEnd

rlPhaseStartTest
rlRun "./ipxe-script.exp"

rlAssertGrep "Open Source Network Boot Firmware" output.log
rlAssertGrep "iPXE>"          output.log
rlAssertGrep "$TEST_KERNEL_VERSION"    output.log
rlAssertGrep "dracut:/#" output.log
rlAssertGrep "Power down"     output.log
if [ "$TEST_PING_CMD" = "1" ]
then
	rlAssertGrep "64 bytes from" output.log
	rlAssertGrep "seq=5"         output.log
fi
rlAssertNotGrep "Could not boot: Error" output.log
rlAssertNotGrep "Finished: Error"       output.log

rlFileSubmit "output.log"
rlPhaseEnd

rlPhaseStartCleanup
rlRun "rm -fv /var/www/html/{boot.txt,vmlinuz-$TEST_KERNEL_VERSION,initramfs-$TEST_KERNEL_VERSION.img} output.log"
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
