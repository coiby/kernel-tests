#! /bin/bash
#	Copyright (c) 2014 Red Hat, Inc. All rights reserved.
#	GPLv2
#	Author: Yi Chen <yiche@redhat.com>

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1


sendip_install()
{
	which sendip 2> /dev/null && return 0
	rlRun "rm -rf SendIP"
	#SendIP github: https://github.com/rickettm/SendIP
	rlRun "git clone https://github.com/rickettm/SendIP.git" || return 1
	rlRun "pushd SendIP" || return 1
	rlRun "sed -i 's/-Werror//g' Makefile"
	# The CKI test distro already uses a newer C standard
	rlRun "sed -i 's/^CFLAGS=/CFLAGS= -std=gnu23/g' Makefile"
	# with standard gnu23, bool/true/false are keywords. lead to double defined in types.h
	rlRun "sed -i '/typedef int bool;/c\\
	#if defined(__STDC_VERSION__) && (__STDC_VERSION__ > 201710L)\\
	/* bool, true and false are keywords.  */\\
	#else\\
	typedef int bool;\\
	#endif\\
	' types.h"
	rlRun "make"
	rlRun "make install"
	popd
	rlRun "which sendip"
}

kselftest_install()
{
	# upstream kselftest
	rlRun "wget --no-check-certificate ${TEST_URL} -O kselftests.tar.gz" || {
		rlDie "Download kselftests.tar.gz failed"
	}
	rlRun "tar -xf kselftests.tar.gz"
}

packetdrill_install()
{
	which packetdrill 2> /dev/null && return 0
	rlRun "rpm -q bison || dnf -y install bison"
	rlRun "pushd /tmp"
	rlRun "rm -rf packetdrill"
	rlRun "git clone https://github.com/google/packetdrill.git"
	rlRun "pushd packetdrill/gtests/net/packetdrill/"
	rlRun "sed -i 's/-static//g' Makefile"
	rlRun "sed -i 's/^CFLAGS =/CFLAGS = -std=gnu23/g' Makefile.common"
	rlRun "mv types.h types.h.bak"
	rlRun "awk '
	/typedef u8 bool;/ {
		print \"#if defined(__STDC_VERSION__) && (__STDC_VERSION__ > 201710L)\"
		print \"#else\"
		in_block = 1
	}
	{ print }
	/^};/ && in_block {
		print \"#endif\"
		in_block = 0
	}' types.h.bak > types.h"
	make
	popd
	popd
	cp -f /tmp/packetdrill/gtests/net/packetdrill/packetdrill /tmp/packetdrill/gtests/net/common/defaults.sh /usr/local/bin/
}


stop_auditd()
{
	rlRun "sed -i 's/RefuseManualStop=yes/RefuseManualStop=no/g' /usr/lib/systemd/system/auditd.service"
	rlRun "systemctl daemon-reload"
	rlRun "systemctl stop auditd"
}

rlJournalStart
rlPhaseStartSetup
	rlRun "rpm -q git                             || dnf -y install git"
	rlRun "rpm -q iperf3                          || dnf -y install iperf3"
	rlRun "rpm -q gcc                             || dnf -y install gcc"
	rlRun "rpm -q socat                           || dnf -y install socat"
	rlRun "rpm -q nmap-ncat                       || dnf -y install nmap-ncat"
	rlRun "rpm -q ipvsadm                         || dnf -y install ipvsadm"
	rlRun "rpm -q conntrack-tools                 || dnf -y install conntrack-tools"
	rlRun "rpm -q iptables                        || dnf -y install iptables"
	rlRun "rpm -q libmnl-devel                    || dnf -y install libmnl-devel"
	rlRun "rpm -q wget                            || dnf -y install wget"
	rlRun "which sendip                           || sendip_install"
	rlRun "which packetdrill                      || packetdrill_install"
	rlRun "test -d selftests                      || kselftest_install"
	rlRun "pushd selftests/net/netfilter/"
	rlRun "make"
	rlRun "stop_auditd"
rlPhaseEnd

if [ "${ITEMS}x" == "x" ]
then
	ITEMS=$(find . -maxdepth 1 -name "*.sh")
fi

tainted_backup=0
for i in ${ITEMS}
do
	rlPhaseStartTest "${i}"
		rlRun "read tainted_backup < /proc/sys/kernel/tainted"
		rlRun -l "bash ./$i" 0,4 # Pass or SKIP
		[ $? == 4 ] && rlLogWarning "WARN: $i skipped"
		rlRun "diff -u <(echo ${tainted_backup}) <(cat /proc/sys/kernel/tainted)" 0 "Kernel tainted check"
	rlPhaseEnd
done

rlPhaseStartCleanup
	rlRun "popd"
	rlRun "systemctl start auditd"
rlPhaseEnd
rlJournalEnd
