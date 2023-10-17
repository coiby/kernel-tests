#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: libhugetlbfs package test
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
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

. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ./kvercmp.sh

if rlIsRHEL 7 && rlIsRHEL "<=7.8"; then
	TEST_VERSION=${TEST_VERSION:-2.16-13.el7}
elif rlIsRHEL "8" && rlIsRHEL "<=8.2"; then
	TEST_VERSION=${TEST_VERSION:-2.21-16.el8}
fi

ORIG_DIR=$(pwd)

function check_support()
{
	local cfg=/boot/config-$(uname -r)
	grep CONFIG_HUGETLB_PAGE=y $cfg || rlReport Hugepage_support WARN 100

	if ! grep -q hugetlbfs /proc/filesystems ; then
		# Bug 1143877 - hugetlbfs: disabling because there are no supported hugepage sizes
		echo "hugetlbfs not found in /proc/filesystems, skipping test"
		rlReport Test_Skipped_hugetlbfs PASS 99
		exit 0
	fi
	if test -f $ORIG_DIR/CHANGED_DEFHPSZ; then
		if grep -q finish $ORIG_DIR/CHANGED_DEFHPSZ; then
			echo "Test cleanup finished for default_hugepagesz" | tee -a $OUTPUTFILE
			rm -f $ORIG_DIR/CHANGED_DEFHPSZ
			exit 0
		fi
	fi
}

function check_system_mem()
{
	# we need at least 6 hugepages and at least ~128M of memory
	hpagesz=$(awk '/Hugepagesize/ {print $2}' /proc/meminfo)
	if [ -z "$hpagesz" ]; then
		echo "Failed to get Hugepagesize from /proc/meminfo" | tee -a $OUTPUTFILE
		cat /proc/meminfo | tee -a $OUTPUTFILE
		rlReport  Hugepagesize_parse_failed FAIL 1
		exit 0
	fi

	mem_free=$(awk '/MemFree/ {print $2}' /proc/meminfo)
	target_mem=${TESTARGS:-131072}
	if test -z "$TESTARGS"; then
		if [ "$hpagesz" ==  2048 ] && ((512*hpagesz < mem_free)); then
			echo "target_mem: 512 * $hpagesz k" | tee -a $OUTPUTFILE
			target_mem=$((512*hpagesz))
		fi
		# ppc64le we need at least 64 hugepages
		if [ "$hpagesz" == 16384  ] && ((96*hpagesz < mem_free)); then
			echo "target_mem: 64 * $hpagesz k" | tee -a $OUTPUTFILE
			target_mem=$((64*hpagesz))
		fi
	fi

	HMEMSZ=$(($target_mem / 1024))
	HPCOUNT=$(($target_mem / $hpagesz))
	if [ "$HPCOUNT" -lt 6 ]; then
		HPCOUNT=6
		HMEMSZ=$((HPCOUNT * $hpagesz / 1024))
	fi

	if [ -n "$hpagesz" -a "$hpagesz" -gt 0 ]; then
		HPSIZE="$(($hpagesz / 1024))M"
	else
		HPSIZE=0
	fi

	echo "HMEMSZ: $HMEMSZ" | tee -a $OUTPUTFILE
	echo "HPSIZE: $HPSIZE" | tee -a $OUTPUTFILE
	echo "HPCOUNT: $HPCOUNT" | tee -a $OUTPUTFILE
}

function version_check()
{
	if which yum &>/dev/null; then
		yum_cmd=yum
		yum_builddep="yum-builddep"
		yum_downloader="yumdownloader"
		which $yum_builddep &>/dev/null || yum -y install $yum_builddep
		which $yum_downloader &>/dev/null || yum -y install yum-utils
	else
		yum_cmd=dnf
		yum_builddep="dnf builddep"
		yum_downloader="dnf download"
	fi

	local name=libhugetlbfs

	rpm -q ${name} || { echo "install libhugetlbfs";$yum_cmd -y install libhugetlbfs &>/dev/null; }
	rpm -q ${name} || { echo "failed to install libhugetlbfs" && rlDie "in-tree libhugetlbfs install"; }

	local tree_version=$(rpm -q --qf "%{VERSION}" $name)
	local tree_release=$(rpm -q --qf "%{RELEASE}" $name)

	if [ -z "$TEST_VERSION" ]; then
		version=${tree_version}
		release=${tree_release}
	else
		version=${TEST_VERSION%-*}
		release=${TEST_VERSION#*-}
	fi

	WORK_DIR=/root/rpmbuild/BUILD/libhugetlbfs-$version

	if [ "$(echo ${version//./} \> ${tree_version//./} | bc)" = 1 ]; then
		rlLogInfo "Running upgraded version $version-$release"
		upgrade=" -Uvh"
	elif [ "$(echo ${version//./} == ${tree_version//./} | bc)" = 1 ] && [ "$(echo ${release%.*} \> ${tree_release%.*} | bc)" = 1 ]; then
		rlLogInfo "Running upgraded version $version-$release"
		upgrade=" -Uvh"
	elif [ "$(echo ${version//./} == ${tree_version//./} | bc)" = 1 ] && [ "$(echo ${release%.*} == ${tree_release%.*} | bc)" = 1 ]; then
		rlLogInfo "Using in-tree ${name} $(rpm -q ${name}) for testing"
		upgrade=" -ivh --force"
	else
		upgrade=" -Uvh --oldpackage"
		rlLogWarning "Using downgraded ${name} $(rpm -q ${name}) for testing"
	fi
}

function install_build_dependency()
{
	if rlIsRHEL 8; then
		$yum_cmd -y install python3
	fi
	rlRun "sh dependency.sh" 0 "install glibc-static"
}

function build_testsuit_srpm()
{
	local name=libhugetlbfs
	local arch=$(uname -m)
	local repo=${DOWNLOAD_LINK:-http://download.devel.redhat.com/brewroot/packages/libhugetlbfs}
	local spec_path=/root/rpmbuild/SPECS

	if test -f BUILD_DONE; then
		rlLogInfo "test suits ready in $WORK_DIR"
		return
	fi

	rpm -q rpm-build || yum -y install rpm-build

	rlPhaseStartTest "build $version-$release"

	# If we have defined 'yum' key word, we'll download with yum downloader.
	if [[ "$repo" =~ "yum" ]]; then
		rlRun "$yum_downloader --downloadonly ${name}-${version}-${release}.${arch}"
		rlRun "$yum_downloader --downloadonly libhugetlbfs-utils-${version}-${release}.${arch}"
		repo=${repo//yum/}
	fi

	# If we have defined the rpm urls one by one. We download with the url directly.
	if [[ "$repo" =~ ".rpm" ]]; then
		echo "Using direct rpm and srpm download urls: $repo"
		for uri in $repo; do
			curl -sLO $uri || rlDie "downloading $uri"
		done
	else
		rlRun "curl -sLO ${repo}/${version}/${release}/src/${name}-${version}-${release}.src.rpm" || rlDie "$name srpm install"
		rlRun "curl -sLO ${repo}/$version/$release/$arch/${name}-${version}-${release}.${arch}.rpm"
		rlRun "curl -sLO ${repo}/$version/$release/$arch/libhugetlbfs-utils-${version}-${release}.${arch}.rpm"
	fi

	install_build_dependency

	rlRun "rpm -ivh ${name}-${version}-${release}.src.rpm" || rlDie "srpm install"
	rlRun "$yum_builddep -y $spec_path/${name}.spec" || rlDie "install builddep"
	rpm -q ${name}-${version}-${release}.${arch} || { rlRun "rpm $upgrade ${name}-${version}-${release}.${arch}.rpm" || rlDie "upgrade libhugetlbfs"; }
	rlRun "rpm -ivh --force libhugetlbfs-utils-${version}-${release}.${arch}.rpm"
	rlRun "rpmbuild -bp $spec_path/${name}.spec"


	if rlIsRHEL ">=8" && [[ "aarch64 s390x ppc64le" =~ $(uname -m) ]]; then
		rlRun "make -C $WORK_DIR BUILDTYPE=NATIVEONLY all install" || rlDie "compile libhugetlbfs"
	else
		rlRun "make -C $WORK_DIR all install" || rlDie "compile libhugetlbfs"
	fi

	cp -f $WORK_DIR/huge_page_setup_helper.py /usr/bin/
	touch $ORIG_DIR/BUILD_DONE

	rlPhaseEnd
}

function test_setup()
{
	# RHEL7 would fails huge_page_setup_helper.py if no /etc/sysctl.conf
	if [ ! -e "/etc/sysctl.conf" ]; then
		echo "Making empty /etc/sysctl.conf" | tee -a $OUTPUTFILE
		touch /etc/sysctl.conf
		restorecon /etc/sysctl.conf
	fi

	rlPhaseStartSetup

	# Increase our chances of getting huge pages
	rlRun "echo 3 > /proc/sys/vm/drop_caches"
	# Support hugetlbfs?
	rlAssertGrep "hugetlbfs" "/proc/filesystems"
	rlAssertGrep "HugePages_Total" "/proc/meminfo"

	rlLog "Hugepage to allocate: ${HMEMSZ}MB"
	# pre-cleanup
	rlRun "umount -a -t hugetlbfs"
	rlRun "hugeadm --pool-pages-max ${HPSIZE}:0"

	# Set up hugepage
	huge_page_setup_helper.py > hpage_setup.txt <<EOF
${HMEMSZ}
hugepages
hugepages root
EOF
	local ret=$?
	cat hpage_setup.txt | tee -a $OUTPUTFILE

	if [ $ret -ne 0 ]; then
		mem_free=$(awk '/MemFree/ {print $2}' /proc/meminfo)
		grep -q "Refusing to allocate .*, you must leave at least .* for the system" hpage_setup.txt
		# If we get message about low memory and free ram is not at least
		# 10x what the test needs, assume we have low memory or the memory
		# is too fragmented. Skip the test and exit with PASS.
		if [ $? -eq 0 -a $mem_free -lt $(($HMEMSZ * 1024 * 10)) ]; then
			cat /proc/meminfo | tee -a $OUTPUTFILE
			report_result Test_Skipped_Lowmem PASS 99
			exit 0
		fi

		# If we fail for any other reason, report FAIL and exit.
		report_result huge_page_setup FAIL $ret
		exit $ret
	fi

	rlRun "hugeadm --create-mount" 0
	rlRun "pushd ${WORK_DIR}" 0

	rlPhaseEnd

	free_hugepages=$(awk '/HugePages_Free/ {print $2}' /proc/meminfo)
	if [[ x"${ARCH}" == "xaarch64" ]]; then
		if [[ x"${HPSIZE}" == "x512M" && ${free_hugepages} -lt $HPCOUNT && ( -z "${REBOOTCOUNT}" || ${REBOOTCOUNT} -eq 0 ) ]]; then
			rlLog "Have ${free_hugepages} free hugepages of ${HPCOUNT} needed.  Rebooting with 2M hugepages"
			mv /etc/sysctl.conf.backup /etc/sysctl.conf
			grubby --args="default_hugepagesz=2M" --update-kernel /boot/vmlinuz-$(uname -r)
			touch $ORIG_DIR/CHANGED_DEFHPSZ
			rhts-reboot
		fi
	fi
}

function filter_known_issues()
{
	local cver=$(uname -r)

	if grep -q "release 6.[0-9] " /etc/redhat-release; then
		# legacy known issue
		# TODO: BZ
		if uname -r | grep -q 686; then
			KNOWNISSUE_32="$KNOWNISSUE_32 -e \"truncate_above_4GB.*mmap() offset 4GB\""
		fi
	fi

	# single CPU hosts, like KVM make some test fail with "Bad configuration"
	# TODO: fix upstream
	local cpus=$(nproc)
	if [ "$cpus" -lt 2 ]; then
		KNOWNISSUE_32="$KNOWNISSUE_32 -e \"Bad configuration: Atleast online 2 cpus are required\""
		KNOWNISSUE_64="$KNOWNISSUE_64 -e \"Bad configuration: Atleast online 2 cpus are required\""
		KNOWNISSUE_32="$KNOWNISSUE_32 -e \"Bad configuration: sched_setaffinity\""
		KNOWNISSUE_64="$KNOWNISSUE_64 -e \"Bad configuration: sched_setaffinity\""
	fi

	kvercmp "$cver" '4.3'
	if [ $kver_ret -le 0 ]; then
		   KNOWNISSUE_32="$KNOWNISSUE_32 -e \"no fallocate support in kernels before 4.3.0\""
		   KNOWNISSUE_64="$KNOWNISSUE_64 -e \"no fallocate support in kernels before 4.3.0\""
	fi

	# Bug 1006253 libhugetlbfs counters testcase occasionally fails on NUMA systems
	if grep -q "release 7.[0-9]" /etc/redhat-release; then
		kvercmp "$cver" '4.10'
		if [ $kver_ret -le 0 ]; then
			KNOWNISSUE_32="$KNOWNISSUE_32 -e \"^counters.sh.*Bad HugePages\""
			KNOWNISSUE_64="$KNOWNISSUE_64 -e \"^counters.sh.*Bad HugePages\""
		fi
	fi

	# Case isssue. version check is not right for rhel7
	if grep -q "release 7.[0-9]" /etc/redhat-release; then
		kvercmp '3.10' "$cver"
		if [ $kver_ret -le 0 ]; then
			KNOWNISSUE_32="$KNOWNISSUE_32 -e \"misalign.*mmap.*succeeded\""
			KNOWNISSUE_64="$KNOWNISSUE_64 -e \"misalign.*mmap.*succeeded\""
		fi
	fi

	# Bug 1161661 - s390x: zero_filesize_segment (64bit) testcase crashing -> CANTFIX
	# impacts all distros / all kernel versions
	if uname -r | grep -q s390x; then
		KNOWNISSUE_64="$KNOWNISSUE_32 -e \"zero_filesize_segment (1024K: 64):\""
	fi

	# https://bugzilla.redhat.com/show_bug.cgi?id=1628794#c8
	# Same issue occurs on F28
	if grep -q "release 8.*" /etc/redhat-release || [ $(grep "Fedora" /etc/redhat-release | grep -o -E '[0-9]+') -gt 27 ]; then
		KNOWNISSUE_32="$KNOWNISSUE_32 -e \"brk_near_huge\""
		KNOWNISSUE_64="$KNOWNISSUE_64 -e \"brk_near_huge\""
	fi

	# Bug 859906 - open() on tmpfs file with O_DIRECT fails with EINVAL -> WONTFIX
	# impacts all distros / all kernel versions, if /tmp is tmpfs
	if df -T /tmp | tail | grep -q tmpfs; then
		KNOWNISSUE_32="$KNOWNISSUE_32 -e \"^direct .*Bad configuration\""
		KNOWNISSUE_64="$KNOWNISSUE_64 -e \"^direct .*Bad configuration\""
	fi

	# Bug 1631911 - [ALT-7.6] vm/hugepage/libhugetlbfs -fails Page size is too large for configured
	if [ "x${HPSIZE}" == "x512M" ]; then
		KNOWNISSUE_32="$KNOWNISSUE_32 -e \"Page size is too large for configured SEGMENT_SIZE\""
		KNOWNISSUE_64="$KNOWNISSUE_64 -e \"Page size is too large for configured SEGMENT_SIZE\""
	fi

	if [ "$HPCOUNT" -lt 512 ]; then
		KNOWNISSUE_32="$KNOWNISSUE_32 -e \"shm-perms .*Bad configuration:.*512 free hugepages\""
		KNOWNISSUE_64="$KNOWNISSUE_64 -e \"shm-perms .*Bad configuration:.*512 free hugepages\""
	elif [ "$HPCOUNT" -lt 64 ] && uname -m | grep ppc64le; then
		KNOWNISSUE_32="$KNOWNISSUE_32 -e \"shm-perms .*Bad configuration:.*64 free hugepages\""
		KNOWNISSUE_64="$KNOWNISSUE_64 -e \"shm-perms .*Bad configuration:.*64 free hugepages\""
	fi
}

function run_test()
{
	r_test=$1
	testlog=${TESTAREA}/${r_test}_${HPSIZE}.log

	rlRun "./run_tests.py -t $r_test 2>&1 > $testlog"

	rlLog "========== SHOW RUNNING STATISTICS: =========="
	rlRun "tail -n 13 $testlog" 0
	rlLog "==========  END RUNNING STATISTICS  =========="

	rlLog "========== SHOW FAILED CASES IN 32-BIT: =========="
	rlRun "grep \"$HPSIZE: 32\" $testlog | grep -v -e PASS -e SKIP $KNOWNISSUE_32" 1
	rlLog "==========  END FAILED CASES IN 32-BIT  =========="

	if [ x"${ARCH}" != "xi386" ]; then
		rlLog "========== SHOW FAILED CASES IN 64-BIT: =========="
		rlRun "grep \"$HPSIZE: 64\" $testlog | grep -v -e PASS -e SKIP $KNOWNISSUE_64" 1
		rlLog "==========  END FAILED CASES IN 64-BIT  =========="
	fi

	rlFileSubmit $testlog
}


function run_tests()
{
	filter_known_issues

	#Grace Period
	sleep 60

	pushd tests

	if [ $free_hugepages -ge $HPCOUNT ]; then
		rlPhaseStartTest "func"
		run_test func
		rlPhaseEnd

		# stress test takes too long on aarch64
		if [ x"$(uname -m)" != "xaarch64" ]; then
			rlPhaseStartTest "stress"
			run_test stress
			rlPhaseEnd
		else
			# Run 2M hugepage
			if [[ "$hpagesz" != "2048" && ( -z "${REBOOTCOUNT}" || ${REBOOTCOUNT} -eq 0 ) ]]; then
				echo "Setup 2M hugepage for aarch64" | tee -a $OUTPUTFILE
				touch $ORIG_DIR/CHANGED_DEFHPSZ
				grubby --args="default_hugepagesz=2M" --update-kernel /boot/vmlinuz-$(uname -r)
				# setup step has made the backup file, restore it the original before next setup.
				mv /etc/sysctl.conf.backup /etc/sysctl.conf
				rhts-reboot
			fi
		fi
	else
		mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
		hpsize=$(awk '/Hugepagesize/ {print $2}' /proc/meminfo)
		if [ ${mem_total} -gt $((1024 * ${HMEMSZ} * 10)) ]; then
			rlPhaseStart WARN "not_enough_huge_pages"
			rlAssertGreaterOrEqual "Need $HPCOUNT hugepages for test, have: $free_hugepages" $free_hugepages $HPCOUNT
			rlPhaseEnd
		else
			report_result Test_Skipped_HPCOUNT PASS 99
		fi
	fi

}


function test_cleanup()
{
	rlPhaseStartCleanup
		rlRun "popd" 0
		rlRun "umount -a -t hugetlbfs"
		rlRun "hugeadm --pool-pages-max ${HPSIZE}:0"
		rlRun "mv /etc/sysctl.conf.backup /etc/sysctl.conf"
		rm $ORIG_DIR/BUILD_DONE -f
		if test -f $ORIG_DIR/CHANGED_DEFHPSZ; then
			rlRun "grubby --remove-args default_hugepagesz=2M --update-kernel ALL"
			echo finish > $ORIG_DIR/CHANGED_DEFHPSZ
			rhts-reboot
		fi
	rlPhaseEnd
}

rlJournalStart
	check_support
	check_system_mem
	version_check
	build_testsuit_srpm
	test_setup
	run_tests
	test_cleanup
rlJournalEnd
rlJournalPrintText
