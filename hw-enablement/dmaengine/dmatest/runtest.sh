#!/bin/bash
# -*- mode: Shell-script; sh-shell: bash; sh-basic-offset: 4; sh-indentation: 4; coding: utf-8-unix; indent-tabs-mode: t; ruler-mode-show-tab-stops: t; tab-width: 4 -*-
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Copyright (c) 2024 Red Hat, Inc
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Summary: Test idxd dmaengine workqueue with dmatest module
#
# Author: Jerry Snitselaar <jsnitsel@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FILE=$(readlink -f ${BASH_SOURCE[0]})
CDIR=$(dirname $FILE)

if test -z "${DMA_MODNAME}"; then
	test_complete "${RSTRNT_TASKNAME}" "SKIP" "The parameter DMA_MODNAME must be set"
fi

if test -z "${DMA_IOMMU_CONF}"; then
	test_complete "${RSTRNT_TASKNAME}" "SKIP" "The parameter DMA_IOMMU_CONF must be set"
fi

DMA_TESTNAME="${DMA_MODNAME}-${DMA_IOMMU_CONF}-$(basename ${CDIR})"

. "/usr/share/beakerlib/beakerlib.sh" || exit 1
. "${CDIR}/../../../iommu/include/iommu-helper.sh" || exit 1
. "${CDIR}/../include/dmaengine-helper.sh" || exit 1
. "${CDIR}/../include/dsa-helper.sh" || exit 1

if test -z "${DMATEST_MULTITHREADS}"; then
	if test "${DMA_MODNAME}" = "idxd" -o "${DMA_MODNAME}" = "ioatdma"; then
		DMATEST_MULTITHREADS="10"
	fi
elif test $((DMATEST_MULTITHREADS)) -lt 2; then
	DMATEST_MULTITHREADS="2"
fi

if ! test -z "${DMAENG_DEBUG}"; then
	set -x
fi

if ! test -d "${DMA_STATEDIR}"; then
	if is_vendor "intel"; then
		intel_iommu_supported
	fi
	init_state
	init_test_pkgs
	set_config "${DMA_IOMMU_CONF}"
	set_phase "config"
fi

if check_phase "config"; then
	grub_setup "$(get_config)"
fi

case "${DMA_MODNAME}" in
	"idxd")
		idxd_check
		;;
	"ptdma" | "ioatdma")
		;;
	*)
		test_complete "${DMA_TESTNAME}" "SKIP" "DMA_MODNAME ${DMA_MODNAME} is not recognized"
		;;
esac

# IOMMU enabled check
if is_vendor "intel" && ! intel_iommu_enabled; then
	test_complete "${DMA_TESTNAME}" "FAIL" "IOMMU didn't initialize"
elif is_vendor "amd" && ! amd_iommu_enabled; then
	test_complete "${DMA_TESTNAME}" "FAIL" "IOMMU didn't initialize"
fi

# IOMMU state check
iommu_state_check

if check_phase "reboot"; then
	set_phase "run"
fi

if ! check_rebootcount "1"; then
	fail_abort "${DMA_TESTNAME}-pre-test-reboot-check" "Unexpected reboot"
fi
check_dma_faults "${DMA_TESTNAME}-pre-test"

setup_sys

# Single-threaded test using dma channels and dmatest module
case "${DMA_MODNAME}" in
	"idxd")
		dmaengine_enable "dsa0" "wq0.0" "engine0.0"
		dmaengine_test "dsa0" "wq0.0" 3000 1000 0 1 "${DMA_TESTNAME}-memcpy-1-thread"
		dmaengine_disable "dsa0" "wq0.0"
		;;
	"ioatdma" | "ptdma")
		driverCheck "${DMA_MODNAME}"
		dmatest_run 3000 1000 0 1 "${DMA_TESTNAME}-memcpy-1-thread"
		;;
	*)
		test_complete "${DMA_TESTNAME}" "SKIP" "DMA_MODNAME ${DMA_MODNAME} is not recognized"
		;;
esac

# multithreaded test with dmatest for ioatdma and idxd
if ! test -z "${DMATEST_MULTITHREADS}"; then
	if test "${DMA_MODNAME}" = "idxd"; then
		cleanup_sys
		setup_sys

		dmaengine_enable "dsa0" "wq0.0" "engine0.0"
		dmaengine_test "dsa0" "wq0.0" 3000 1000 0 "${DMATEST_MULTITHREADS}" "${DMA_TESTNAME}-memcpy-${DMATEST_MULTITHREADS}-threads"
		dmaengine_disable "dsa0" "wq0.0"
	elif test "${DMA_MODNAME}" = "ioatdma"; then
		dmatest_run 3000 1000 0 "${DMATEST_MULTITHREADS}" "${DMA_TESTNAME}-memcpy-${DMATEST_MULTITHREADS}-threads"
	fi
fi

cleanup_sys
grub_cleanup

# did we reboot during the test?
if ! check_rebootcount "1"; then
	fail_abort "${DMA_TESTNAME}-post-test-reboot-check" "Unexpected reboot"
fi

grub_exit
cleanup_state

rstrnt-report-result "${DMA_TESTNAME}" "PASS"
