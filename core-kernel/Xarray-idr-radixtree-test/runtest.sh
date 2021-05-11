#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Description: Xarray-idr-radixtree-test
# Author: Li Wang <liwang@redhat.com>

. ../../cki_lib/libcki.sh           || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

set -o pipefail

CKI_RADIXTREE_URL=${CKI_RADIXTREE_URL:-https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/linux-5.10.tar.gz}

function install_dependency()
{
	yum="yum -y install"

	$yum \
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

function build_radixtree()
{
	wget --no-check-certificate ${CKI_RADIXTREE_URL}
	tar xf linux-*.tar.gz
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
	cki_run_cmd_pos "rm -fr linux-*/ *.log"

	return $CKI_PASS
}

cki_main
exit $?
