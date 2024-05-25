#!/bin/bash
# -*- mode: Shell-script; sh-shell: bash; sh-basic-offset: 4; sh-indentation: 4; coding: utf-8-unix; indent-tabs-mode: t; ruler-mode-show-tab-stops: t; tab-width: 4 -*-
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Copyright (c) 2024 Red Hat, Inc
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Summary: Helper code for testing Intel DSA and IAA devices
#
# Author: Jerry Snitselaar <jsnitsel@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Expected PARAMS:
#
# DMA_MODNAME - string of name for module being tested
# DMA_STATEDIR - location where state is kept
# DMATEST_MULTITHREADS - if set, then the number of threads per channel
# DMAENG_DEBUG - Enabling debugging messages and tracing

if ! test -z "${DMAENG_DEBUG}"; then
	set -x
fi

accel_config_test_run ()
{
	declare -i ret=0
	if test "$(cat /sys/bus/dsa/devices/dsa0/pasid_enabled)" = "1"; then
		eval "${2}" > "${1}.log" 2>&1
		ret=$?
		check_dma_faults "${1}"
		if test $ret -eq 0; then
			test_continue "${1}" "PASS" "test script passed" "${1}.log"
		elif test $ret -eq 77; then
			 test_continue "${1}" "SKIP" "test script skipped test" "${1}.log"
		else
			test_continue "${1}" "FAIL" "test script failed" "${1}.log"
		fi
	else
		if ! is_intel_pasid_supported; then
			test_complete "${1}" "SKIP" "Platform issue: pasid not supported"
		else
			test_complete "${1}" "FAIL" "pasid is not enabled"
		fi
	fi
}

idxd_check ()
{
	if test "$(lspci -d8086:0b25 | wc -l)" = "0"; then
		test_complete "${DMA_TESTNAME}-idxd-check" "SKIP" "No idxd devices on this system"
	fi
}

iaa_check ()
{
	if [ "$(lspci -d8086:0cfe | wc -l)" != "0" ]; then
		acvers=$(rpm -q --qf="%{VERSION}" accel-config)
		if test "${acvers}" = "4.1.3"; then
			test_complete "${DMA_TESTNAME}-iaa-check" "SKIP" "iax device enabled system needs accel config 4.1.6 for testing"
		fi
		touch "${DMA_STATEDIR}/iaa_enabled"
	else
		test_complete "${DMA_TESTNAME}-iaa-check" "SKIP" "No iax devices on this system"
	fi
}

# $1 - dsa device
# $2 - dsa workqueue
dmaengine_disable ()
{
	if ! test -f "/sys/bus/dsa/devices/${2}/state"; then
		test_complete "${DMA_TESTNAME}-dsa-dmaengine-disable" "FAIL" "sysfs state entry for DSA workqueue ${2} does not exist"
	fi

	if ! test -f "/sys/bus/dsa/devices/${1}/state"; then
		test_complete "${DMA_TESTNAME}-dsa-dmaengine-disable" "FAIL" "sysfs state entry for DSA device ${1} does not exist"
	fi

	if lsmod | grep -q dmatest; then
		modprobe -rq dmatest
	fi

	wqstate=$(cat "/sys/bus/dsa/devices/${2}/state")
	devstate=$(cat "/sys/bus/dsa/devices/${1}/state")

	if [ "$wqstate" = "enabled" ];
	then
		accel-config disable-wq "${1}/${2}"
	fi

	if [ "$devstate" = "enabled" ];
	then
		accel-config disable-device "${1}"
	fi

	return 0
}

# $1 - dsa device
# $2 - dsa workqueue
# $3 - dsa engine
dmaengine_enable ()
{
	if ! lsmod | grep -q idxd; then
		modprobe -q idxd
	else
		dmaengine_disable "${1}" "${2}"
	fi

	accel-config config-wq "${1}/${2}" -g 0 -p 5 -s 8 -y kernel -m dedicated -c 32 -n guest1 --driver-name dmaengine
	accel-config config-engine "${1}/${3}" --group-id=0
	accel-config enable-device "${1}"
	accel-config enable-wq "${1}/${2}"

	wqstate=$(cat "/sys/bus/dsa/devices/${2}/state")
	devstate=$(cat "/sys/bus/dsa/devices/${1}/state")

	if test "${wqstate}" != "enabled"; then
		test_complete "${DMA_TESTNAME}-dsa-dmaengine-enable" "FAIL" "DSA workqueue ${2} is not enabled"
	fi
	if test "${devstate}" != "enabled"; then
		test_complete "${DMA_TESTNAME}-dsa-dmaengine-enable" "FAIL" "DSA device ${1} is not enabled"
	fi

	return 0
}

# $1 - dsa device
# $2 - dsa workqueue
# $3 - timeout
# $4 - interations
# $5 - dmatest (0 - memcpy, 1 - memset)
# $6 - threads per channel
# $7 - sub-test name
dmaengine_test ()
{
	local dsapci="$(readlink /sys/bus/dsa/devices/${1} | cut -d '/' -f6)"

	if ! exists /sys/class/dma/dma*chan*; then
		test_complete "${DMA_TESTNAME}-dsa-dmaengine-test" "FAIL" "No dma channel devices in /sys/class/dma"
		return
	fi

	for c in /sys/class/dma/dma*chan*;
	do
		pcibdf="$(readlink ${c}/device | cut -d '/' -f4)"
		if test "${dsapci}" = "${pcibdf}"; then
			modpci="$(lspci -k -s ${pcibdf} | grep 'driver in us' | cut -d ' ' -f5)"
			if test "${DMA_MODNAME}" = "${modpci}"; then
				dmachans+=("${c}")
				break
			fi
		fi
	done

	if test "${#dmachans[@]}" = "0"; then
		dmaengine_disable "${1}" "${2}"
		test_complete "${DMA_TESTNAME}-dsa-dmaengine-test" "FAIL" "Couldn't find dma channel tied to ${1}"
		return
	fi

	modprobe -q dmatest
	dmatest_run "${3}" "${4}" "${5}" "${6}" "${7}"
	modprobe -rq dmatest
}
