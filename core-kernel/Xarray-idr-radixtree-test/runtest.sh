#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Description: Xarray-idr-radixtree-test
# Author: Li Wang <liwang@redhat.com>

. ../../cki_lib/libcki.sh           || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

set -o pipefail

function install_dependency()
{
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
}

function get_running_kernel_src()
{
	running_kernel=$(uname -r | sed "s/+debug//" | sed "s/\.`arch`//")

	echo $running_kernel | grep -q -v 'el[0-9]\|fc\|eln'

	if [ $? -eq 0 ]; then
		cki_log "detected upstream kernel..."
		# For CKI upstream kernels, the source is extracted under /usr/src/kernels/
		# this is done as part of distribution/kpkginstall (Boot test)
		cki_log "Copying /usr/src/kernels/${running_kernel} to linux-${running_kernel}"
		# Not using rlRun as sometimes the function causes "Segmentation fault"
		cp -r /usr/src/kernels/${running_kernel} linux-${running_kernel}
	else
		kernelpkg="kernel"
		# check if it is running kernel-rt
		echo $running_kernel | grep -q -v '\.rt'
		if [ $? -eq 1 ]; then
			kernelpkg="kernel-rt"
		fi
		cki_log "detected rhel/fedora/ark kernel..."
		echo $running_kernel | grep -q -v 'fc'
		if [ $? -ne  0 ]; then
			cki_log "workaround to find srpm name for ark kernels..."
			# ARK kernel don't always have disttag correct
			# workaround to find the srpm version on cki repo
			running_kernel=$(dnf -q --disablerepo="*" --enablerepo="kernel-cki" list --all "${kernelpkg}.src" --showduplicates \
				| awk '{print$2}' | tail -1)
		fi
		cki_run_cmd_pos "dnf download --source ${kernelpkg}-${running_kernel}"
		rpm -ivh kernel-*.src.rpm
		tar xf /root/rpmbuild/SOURCES/linux-*.tar.xz -C .
	fi
}

function build_radixtree()
{
	get_running_kernel_src

	cki_cd linux-*/
	make -C tools/testing/radix-tree/
	[ -f tools/testing/radix-tree/main ]     || return 1
	[ -f tools/testing/radix-tree/xarray ]   || return 1
	[ -f tools/testing/radix-tree/idr-test ] || return 1
	cki_pd
}

function run_radixtree()
{
	t_name=$1

	case $t_name in
	"xarray" | "idr-test" | "main")
		linux-*/tools/testing/radix-tree/${t_name} > ${t_name}.log
		;;
	*)
		cki_log "No test $t_name in the tools/testing/radix-tree/" && return 1
		;;
	esac
}

function startup()
{
	cki_run_cmd_pos "install_dependency"
	cki_run_cmd_pos "build_radixtree"

	return $CKI_PASS
}

function runtest()
{
	cki_run_cmd_pos "run_radixtree xarray"
	cki_upload_log_file xarray.log

	cki_run_cmd_pos "run_radixtree idr-test"
	cki_upload_log_file idr-test.log

	cki_run_cmd_pos "run_radixtree main"
	cki_upload_log_file main.log

	return $CKI_PASS
}

function cleanup()
{
	cki_run_cmd_pos "rm -fr linux-*/ *.log *.tar.*"

	return $CKI_PASS
}

cki_main
exit $?
