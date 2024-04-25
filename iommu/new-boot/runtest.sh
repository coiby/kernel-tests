#!/bin/bash
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Copyright (c) 2024 Red Hat, Inc
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Summary: Test intel_iommu boot with Scalable Mode and batched
#		   iotlb invalidation.
#
# Author: Jerry Snitselaar <jsnitsel@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FILE=$(readlink -f ${BASH_SOURCE[0]})
CDIR=$(dirname $FILE)

if test -z "${DMA_MODNAME}"; then
	test_complete "SKIP" "${RSTRNT_TASKNAME} requires DMA_MODNAME to be set"
fi

if test -z "${DMA_IOMMU_CONF}"; then
	test_complete "SKIP" "${RSTRNT_TASKNAME} requires DMA_IOMMU_CONF to be set"
fi

DMA_TESTNAME="${DMA_MODNAME}-new-boot-${DMA_IOMMU_CONF}"

. "/usr/share/beakerlib/beakerlib.sh" || exit 1
. "${CDIR}/../include/iommu-helper.sh" || exit 1

if ! test -z "${IOMMU_DEBUG}"; then
	set -x
fi

rlJournalStart
{
	if ! test -d "${DMA_STATEDIR}"; then
		iommu_supported_check
		init_state
		set_config "${DMA_IOMMU_CONF}"
		set_phase "config"
	fi

	if check_phase "config"; then
	   grub_setup "$(get_config)"
	fi

	iommu_enabled_check

	iommu_state_check

	if check_phase "reboot"; then
	   set_phase "run"
	fi

	rlPhaseStart FAIL "${DMA_TESTNAME} reboot and dma faults check"
	{
		if ! check_rebootcount "1"; then
			fail_abort "${DMA_TESTNAME} Unexpected reboot"
		fi
		check_dma_faults "${DMA_TESTNAME} dma faults check"
	}
	rlPhaseEnd

	grub_cleanup

	rlPhaseStartCleanup "${DMA_TESTNAME} cleanup"
	{
		grub_exit
		cleanup_state
	}
	rlPhaseEnd

	rstrnt-report-result "${DMA_TESTNAME} test complete" "PASS"
}
rlJournalEnd
