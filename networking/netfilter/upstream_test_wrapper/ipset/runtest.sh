#!/bin/bash
#   Description: wrapper of the ipset upstream selftest
#   Author: Yi Chen  <yiche@redhat.com>

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1


libtool_install()
{
	local ret=0
	test -e libtool-2.4.2.tar.gz || { wget http://ftpmirror.gnu.org/libtool/libtool-2.4.2.tar.gz; }
	tar zxf libtool-2.4.2.tar.gz
	cd libtool-2.4.2 || return 1
	./configure		||((ret+=1))
	make			||((ret+=1))
	make install	||((ret+=1))
	cd -
	return $ret
}
netmask_install()
{
	dnf -y install texinfo
	git clone https://github.com/tlby/netmask.git || return 1
	pushd netmask/ || return 1
	./autogen
	./configure
	make
	make install
	popd
	which netmask >/dev/null 2>&1
}

sendip_install()
{
	#SendIP github: https://github.com/rickettm/SendIP
	git clone https://github.com/rickettm/SendIP.git || return 1
	pushd SendIP || return 1
	sed -i 's/-Werror//g' Makefile
	make
	make install
	popd
	which sendip >/dev/null 2>&1
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
	rlRun "sed -i 's/exit 1/# exit 1/g' ./tests/runtest.sh"	# don't exit when fail,finish test
	rlRun "popd"
}

rlJournalStart
	rlPhaseStartSetup "ipset upstream test installing"
		rlRun "dnf -y install libmnl-devel libtool-ltdl-devel automake autoconf libtool elfutils-libelf-devel git"
		rlRun "dnf -y install kernel-modules-extra-$(uname -r) kernel-devel-$(uname -r)"
		which sendip || rlRun "sendip_install"
		which netmask || rlRun "netmask_install"
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
