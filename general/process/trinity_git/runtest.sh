#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/process/git_trinity
#   Description: run syscall fuzz with upstream repo
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include rhts environment
. /usr/share/beakerlib/beakerlib.sh ||  exit 1

# Enable TMT testing for RHIVOS
. ../../../automotive/include/rhivos.sh
declare -F kernel_automotive && kernel_automotive && is_rhivos=1 || is_rhivos=0


# trinity-9f6f9f916da3 (v1.8)
# trinity-865ac5d8 (v1.9)
# trinity-80fb6169 (v1.9+ (20220109))
# trinity-6a17c218 (20240521)
if rlIsRHEL ">=9.5" || rlIsCentOS ">=9.5" || rlIsFedora; then
	testversion=${testversion:-"trinity-6a17c218"}
elif rlIsRHEL ">=9" || rlIsCentOS ">=9"; then
	testversion=${testversion:-"trinity-80fb6169"}
elif rlIsRHEL ">=8" || rlIsCentOS ">=8"; then
	testversion=${testversion:-"trinity-4d2343bd"}
else
	testversion=${testversion:-"trinity-865ac5d8"}
fi
trinity_pkg=${testversion}.tgz

trap 'pkill -f trinity -9; pkill -f make' SIGINT SIGQUIT SIGTERM

# ignore this message from restraint dmesg detector (this is in rhel9)
export FALSESTRINGS="${FALSESTRINGS:+$FALSESTRINGS|}WARNING: The mand mount option has been deprecated and"
rlLog "FALSESTRINGS: $FALSESTRINGS"

function get_lookaside()
{
	[ -z "$LOOKASIDE" ] && LOOKASIDE=http://download.devel.redhat.com/qa/rhts/lookaside/
	rpm -q wget || yum -y install wget > /dev/null
	wget "$LOOKASIDE/$trinity_pkg"
	if [ $? -ne 0  ]; then
		rlDie "Aborting test because failed to download the trinit package from lookaside, please check network issue."
	fi
	tar -zxvf "$trinity_pkg"
}

# shellcheck disable=SC2120
function patch_apply()
{
	local p
	local pl
	local patch_method=${1:-patch}
	local patch_cmd="git am"
	local pc

	if [ "$patch_method" = patch ]; then
		patch_cmd="patch -p1 <"
	fi

	! test -d "$testversion" && return 0
	pushd "${testversion}-patches"
	pl=$(ls *.patch)
	popd

	pushd "${testversion}"
	for p in $pl; do
		echo "applying $p"
		pc=$patch_cmd
		pc+=" ../${testversion}-patches/$p"
		echo patch command: $pc
		eval "$pc"
	done
	popd
}

function test_setup()
{
	SCHED_NR_CPU=$(nproc)

	#  debug to see if the panic was caused by the dlci module
	# [Bug 1944540] RHEL8: s390x: kernel BUG at mm/slub.c
	if uname -r | grep s390x; then
		lsmod | grep dlci && rmmod dlci
		find "/usr/lib/modules/$(uname -r)/" -name "dlci*" -exec mv {} ./ \;
	fi

	# yum -y install json-c-devel json-c
	# rpm -q util-linux || yum -y install util-linux
	which trinity && return
	# Can't clone in beaker env when automation. prepare the head into lookaside
	# rlRun "git clone https://github.com/kernelslacker/trinity.git" 0-255
	test -d testversion || get_lookaside
	patch_apply
	rlRun "pushd $testversion"
	gcc_version=$(gcc --version | awk '{print $3; exit 0}')
	if rlTestVersion "$gcc_version" ">=" 14; then
		rlRun "CFLAGS=-Wno-implicit-function-declaration ./configure"
	else
		rlRun "./configure"
	fi
	rlRun "make -j ${SCHED_NR_CPU}" || rlDie "compile"
	if [ $is_rhivos == 1 ];then
		#rlRun "echo \"DESTDIR=\"/usr/local\"\" >> /etc/environment"
		rlRun "export DESTDIR=\"/usr/local\""
	fi
	rlRun "make install"
	rlRun "popd"

	if (rlIsRHEL 9 || rlIsCentOS 9) && [ "$(uname -m)" = "ppc64le" ]; then
		export SKIP_TESTS="-x futex"
		rlLogInfo "skip futex test on ppc64le becuase of RHEL-2006"
	fi
}

function test_syscalls_trinity()
{
	rlPhaseStartTest trinity
		trinity_duration=${trinity_duration:-3600}
		rlRun "timeout --signal=SIGTERM $trinity_duration ./trinity_as_user.sh" 0-255
	rlPhaseEnd
}



rlJournalStart
	rlPhaseStartSetup
		test_setup
	rlPhaseEnd
	test_syscalls_trinity
	rlPhaseStartCleanup
		rlRun "pkill -xf trinity" 0-255
		rlRun "pkill -xf trinity -9" 0-255
		rlRun "test -d $testversion && rm -fr $testversion" 0-255
		uname -r | grep s390x && find . -name "dlci*" -exec mv {} "/usr/lib/modules/$(uname -r)/" \;
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

