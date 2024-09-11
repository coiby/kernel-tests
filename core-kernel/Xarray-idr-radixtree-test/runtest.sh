#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Description: Xarray-idr-radixtree-test
# Author: Li Wang <liwang@redhat.com>

. ../../cki_lib/libcki.sh           || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

set -o pipefail

function install_dependency()
{
	local RC=0

	dnf="dnf -y install"

	$dnf \
		tar \
		autoconf \
		automake \
		make \
		clang \
		gcc \
		pkg-config \
		bison \
		flex \
		openssl-devel \
		dwarves \
		elfutils-libelf-devel \
		wget \
		bzip2 \
		unzip \
		libasan \
		libubsan \
		userspace-rcu \
		userspace-rcu-devel

	rpm -q dwarves               --quiet	|| RC=1
	rpm -q libasan               --quiet	|| RC=1
	rpm -q libubsan              --quiet	|| RC=1
	rpm -q userspace-rcu         --quiet	|| RC=1
	rpm -q userspace-rcu-devel   --quiet	|| RC=1

	if [ $RC -eq 1 ]; then
		rlLog "Failed to install dependecy packages"
		rstrnt-report-result "${TEST}" WARN
		exit 1
	fi

}

function get_running_kernel_src()
{
	running_kernel=$(uname -r | sed "s/+debug//" | sed "s/\.`arch`//")

	echo $running_kernel | grep -q -v 'el[0-9]\|fc\|eln'

	if [ $? -eq 0 ]; then
		rlLog "detected upstream kernel..."
		# For CKI upstream kernels, the source is extracted under /usr/src/kernels/
		# this is done as part of distribution/kpkginstall (Boot test)
		rlLog "Copying /usr/src/kernels/${running_kernel} to linux-${running_kernel}"
		# Not using rlRun as sometimes the function causes "Segmentation fault"
		cp -r /usr/src/kernels/${running_kernel} linux-${running_kernel}
	else
		cki_download_kernel_src_rpm
		rpm -ivh kernel-*.src.rpm
		tar xf /root/rpmbuild/SOURCES/linux-*.tar.xz -C .
	fi
}

function build_radixtree()
{
	get_running_kernel_src

	pushd linux-*/
	patch -d tools/testing/radix-tree/ < ../patch/disable-iteration-test.patch
	make -C tools/testing/radix-tree/
	[ -f tools/testing/radix-tree/main ]     || return 1
	[ -f tools/testing/radix-tree/xarray ]   || return 1
	[ -f tools/testing/radix-tree/idr-test ] || return 1
	popd
}

function run_radixtree()
{
	t_name=$1

	case $t_name in
	"xarray" | "idr-test" | "main")
		linux-*/tools/testing/radix-tree/${t_name} 2>&1 | tee ${t_name}.log
		return ${PIPESTATUS[0]}
		;;
	*)
		rlLog "No test $t_name in the tools/testing/radix-tree/" && return 1
		;;
	esac
}

function startup()
{
	rlRun -l "install_dependency"
	rlRun -l "build_radixtree"

	return $CKI_PASS
}

function runtest()
{
	rlRun -l "run_radixtree xarray"
	cki_upload_log_file xarray.log

	rlRun -l "run_radixtree idr-test"
	cki_upload_log_file idr-test.log

#	Disable running main test case as it returns too many false positives
#	https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/787#note_1058092780
#	rlRun -l "run_radixtree main"
#	cki_upload_log_file main.log

	return $CKI_PASS
}

function cleanup()
{
	rlRun -l "rm -fr linux-*/ *.log *.tar.*"

	return $CKI_PASS
}

cki_main
exit $?
