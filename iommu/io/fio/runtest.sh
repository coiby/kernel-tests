#!/bin/bash -Ex
## -*- mode: Shell-script; sh-shell: bash; sh-basic-offset: 4; sh-indentation: 4; coding: utf-8; indent-tabs-mode: t; ruler-mode-show-tab-stops: t; tab-width: 4 -*-
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Copyright (c) 2024 Red Hat, Inc
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Summary: Test io using fio on system with iommu
#	   in different configurations
#
# Author: Jerry Snitselaar <jsnitsel@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FILE=$(readlink -f ${BASH_SOURCE[0]})
CDIR=$(dirname $FILE)

if test -z "${DMA_IOMMU_FIO}"; then
	test_complete "${RSTRNT_TASKNAME}" "SKIP" "requires DMA_IOMMU_FIO to be set"
fi

if test -z "${DMA_MODNAME}"; then
	test_complete "${RSTRNT_TASKNAME}" "SKIP" "requires DMA_MODNAME to be set"
fi

if test -z "${DMA_IOMMU_CONF}"; then
	test_complete "${RSTRNT_TASKNAME}" "SKIP" "requires DMA_IOMMU_CONF to be set"
fi

DMA_TESTNAME="${DMA_MODNAME}-io-fio-${DMA_IOMMU_FIO}-${DMA_IOMMU_CONF}"

. "/usr/share/beakerlib/beakerlib.sh" || exit 1
. "${CDIR}/../../include/iommu-helper.sh" || exit 1

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
	fail_abort "${DMA_TESTNAME}-pre-test-reboot-check" "Unexpected reboot"
fi
check_dma_faults "${DMA_TESTNAME}-pre-test"

NJOBS="${NJOBS:=1}"
RUNTIME="${RUNTIME:=2m}"
IODEPTH="${IODEPTH:=4}"
FILESZ="${FILESZ:=250mi}"

NCPUS="$(nproc)"
if ((NJOBS > (NCPUS / 2))); then
	NJOBS="$((NCPUS / 2))"
	if test "${NJOBS}" = "0"; then
		NJOBS="1"
	fi
fi

declare -i half_space

disk_avail_k="$(df /mnt/scratchspace -k --output=avail | grep -v Avail)"
half_space=$((disk_avail_k / 2))

repat_filesz="([0-9]+)([kKmMgG]{0,1}[i]{0,1})"
if [[ ${FILESZ} =~ ${repat_filesz} ]]; then
	size="${BASH_REMATCH[1]}"
	units="${BASH_REMATCH[2]}"
	case "${units}" in
		"mi" | "Mi")
			size=$((size * 2**10))
			;;
		"m" | "M")
			size=$((size * 1000))
			;;
		"gi" | "Gi")
			size=$((size * 2**20))
			;;
		"g" | "G")
			size=$((size * 1000000))
			;;
	esac
	if (((size * NJOBS * 4) > half_space)); then
		FILESZ="$((half_space / (NJOBS * 4)))ki"
	fi
else
	echo "${DMA_TESTNAME} didn't recognize FILESZ, using default of 250mi"
	FILESZ="250mi"
fi

RUNTIME=${RUNTIME} FILESZ=${FILESZ} IODEPTH=${IODEPTH} NJOBS=${NJOBS} fio ${DMA_IOMMU_FIO}
if test $? -ne 0; then
	test_complete "${DMA_TESTNAME}" "FAIL" "fio exited with failure code"
fi

check_dma_faults "${DMA_TESTNAME}-fio"

# post test reboot check
if ! check_rebootcount "1"; then
	fail_abort "${DMA_TESTNAME}-post-test-reboot-check" "Unexpected reboot"
fi
grub_exit
cleanup_state
rstrnt-report-result "${DMA_TESTNAME}" "PASS"
