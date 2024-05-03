#!/bin/bash
# -*- mode: Shell-script; sh-shell: bash; sh-basic-offset: 4; sh-indentation: 4; coding: utf-8-unix; indent-tabs-mode: t; ruler-mode-show-tab-stops: t; tab-width: 4 -*-
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Copyright (c) 2024 Red Hat, Inc
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Summary: Test iommu boot with various configurations
#
# Author: Jerry Snitselaar <jsnitsel@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FILE=$(readlink -f ${BASH_SOURCE[0]})
CDIR=$(dirname $FILE)

if test -z "${DMA_MODNAME}"; then
	test_complete "${RSTRNT_TASKNAME}" "SKIP" "requires DMA_MODNAME to be set"
fi

if test -z "${DMA_IOMMU_CONF}"; then
	test_complete "${RSTRNT_TASKNAME}" "SKIP" "requires DMA_IOMMU_CONF to be set"
fi

DMA_TESTNAME="${DMA_MODNAME}-new-boot-${DMA_IOMMU_CONF}"

. "/usr/share/beakerlib/beakerlib.sh" || exit 1
. "${CDIR}/../include/iommu-helper.sh" || exit 1

if ! test -z "${IOMMU_DEBUG}"; then
	set -x
fi

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

if ! check_rebootcount "1"; then
	fail_abort "${DMA_TESTNAME}-reboot-check" "Unexpected reboot"
fi
check_dma_faults "${DMA_TESTNAME}-post-boot"

grub_cleanup

grub_exit
cleanup_state

rstrnt-report-result "${DMA_TESTNAME}" "PASS"
