#!/bin/bash
#   Description: wrapper of the ipset upstream selftest
#   Author: Yi Chen  <yiche@redhat.com>

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

libmnl_install()
{
	rm -rf libmnl
	git clone git://git.netfilter.org/libmnl || {
		rlDie "Fetch libmnl failed"
	}

	pushd libmnl
	make clean
	./autogen.sh
	./configure --enable-static --prefix="$PWD/install" || {
		rlDie "libmnl: configure failed"
	}
	make -j $(nproc) || { rlDie "libmnl: make failed"; }
	make install || { rlDie "libmnl: make install failed"; }
	popd
	export PKG_CONFIG_PATH="$(realpath libmnl)/install/lib/pkgconfig:${PKG_CONFIG_PATH}"
}

ipset_install()
{
	rlRun "export PKG_CONFIG_PATH=\"$(realpath libmnl)/install/lib/pkgconfig:${PKG_CONFIG_PATH}\""
	if [ ! -d ipset ];then
		rlRun "git clone git://git.netfilter.org/ipset" || rlDie "Fetch git://git.netfilter.org/ipset failed"
	fi
	rlRun "pushd ipset"
	rlRun "./autogen.sh"
	rlRun "./configure"
	rlRun "make clean"
	rlRun "make -j $(nproc)" || riDie "ipset didn't build successfully"
	rlRun "sed -i 's/exit 1/# exit 1/g' ./tests/runtest.sh" # don't exit when fail,finish test
	rlRun "popd"
}

rlJournalStart
	rlPhaseStartSetup "ipset upstream test installing"
		rlRun "dnf -y install libmnl-devel libtool-ltdl-devel automake autoconf libtool elfutils-libelf-devel git ipcalc"
		which sendip || rlRun "sendip_install"
		test -e libmnl/install/lib/libmnl.so.0 || rlRun "libmnl_install"
		ldd ipset/src/ipset | grep 'libmnl/install/lib/libmnl.so.0' || {
			rlRun "ipset_install"
		}
		rlRun "ldd ipset/src/ipset | grep 'libmnl/install/lib/libmnl.so.0'" || rlDie "Make sure upstream libmnl enabled"
	rlPhaseEnd

	rlPhaseStartTest "ipset upstream test"
		rlRun "pushd ipset"
		rlRun "make tests|tee ../ipset.log" 0-1
		rlRun "popd"
		if grep -q "All tests are passed" ipset.log
		then
			rlPass "Test completely done"
		else
			rlFail "Test didn't finish"
		fi #"All test are passed" means test finished, not really all passed.

		sed -n -e'/FAILED$/{p;n;p;x;p;x;}' ipset.log 1> result.log
		if [ -s result.log ]
		then
			rlFail "At least one test failed"
			rstrnt-report-log -l result.log
		else
			rlPass "All tests are passed"
		fi
		rstrnt-report-log -l ipset.log
	rlPhaseEnd

	rlPhaseStartCleanup
		unset PKG_CONFIG_PATH
	rlPhaseEnd
rlJournalEnd
