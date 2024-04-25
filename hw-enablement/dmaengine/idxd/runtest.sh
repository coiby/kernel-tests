#!/bin/bash
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Copyright (c) 2024 Red Hat, Inc
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Summary: Test idxd user workqueue with dsa_config_test_runner.sh
#
# Author: Jerry Snitselaar <jsnitsel@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FILE=$(readlink -f ${BASH_SOURCE[0]})
CDIR=$(dirname $FILE)

DMA_MODNAME="idxd"

if test -z "${DMA_IOMMU_CONF}" -o -z "${IDXD_ACCFG_TEST}"; then
	test_complete "SKIP" "${DMA_TESTNAME} requires the DMA_IOMMU_CONF and IDXD_ACCFG_TEST variables to be set"
fi

DMA_TESTNAME="${DMA_MODNAME}-${DMA_IOMMU_CONF}-${IDXD_ACCFG_TEST}"

. "/usr/share/beakerlib/beakerlib.sh" || exit 1
. "${CDIR}/../../../iommu/include/iommu-helper.sh" || exit 1
. "${CDIR}/../include/dmaengine-helper.sh" || exit 1
. "${CDIR}/../include/dsa-helper.sh" || exit 1

if ! test -z "${DMAENG_DEBUG}"; then
	set -x
fi

rlJournalStart
{
	if ! test -d "${DMA_STATEDIR}"; then
		intel_iommu_supported
		init_state
		accel_config_test_install
		set_config "${DMA_IOMMU_CONF}"
		set_phase "config"
	fi

	if check_phase "config"; then
	   grub_setup "$(get_config)"
	fi

	case "${IDXD_ACCFG_TEST}" in
		"dsa_conf_test_runner" | "dsa_user_test_runner")
			idxd_check
			;;
		"iaa_user_test_runner")
			idxd_check
			iaa_check
			;;
		*)
			test_complete "SKIP" "${DMA_TESTNAME} unknown IDXD test name: ${IDXD_ACCFG_TEST}"
			;;
	esac

	if ! is_sm_supported; then
		test_complete "SKIP" "${DMA_TESTNAME} scalable mode is not supported"
	fi

	if ! intel_iommu_enabled; then
		test_complete "FAIL" "${DMA_TESTNAME} IOMMU didn't initialize"
	fi

	iommu_state_check

	if check_phase "reboot"; then
	   set_phase "run"
	fi

	rlPhaseStart FAIL "${DMA_TESTNAME} pre-test reboot and dma faults check"
	{
		if ! check_rebootcount "1"; then
			fail_abort "Unexpected reboot"
		fi
		check_dma_faults "${DMA_TESTNAME} pre-test dma faults check"
	}
	rlPhaseEnd

	rlPhaseStartTest "${DMA_TESTNAME} ${IDXD_ACCFG_TEST}"
	{
		accel_config_test_run "${DMA_TESTNAME} ${IDXD_ACCFG_TEST}" "/usr/libexec/accel-config/test/${IDXD_ACCFG_TEST}.sh" "0,77"
	}
	rlPhaseEnd

	if ! check_rebootcount "1"; then
		fail_abort "${DMA_TESTNAME} Unexpected reboot"
	fi

	grub_exit
	cleanup_state

	rstrnt-report-result "${DMA_TESTNAME} test complete" "PASS"
}
rlJournalEnd
