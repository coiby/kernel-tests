#!/bin/bash
# shellcheck disable=SC2076
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Copyright (c) 2024 Red Hat, Inc
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Summary: Helper code for testing with DMAEngine subsystem
#
# Author: Jerry Snitselaar <jsnitsel@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Expected PARAMS:
#
# DMA_MODNAME - string of name for module being tested
# DMATEST_MULTITHREADS - if set, then the number of threads per channel
# DMAENG_DEBUG - Enabling debugging messages and tracing
# DMA_STATEDIR - location where state is kept

if test -z "${DMA_MODNAME}"; then
	test_complete "${DMA_TESTNAME}" "SKIP" "requires the environment variable DMA_MODNAME to be set"
fi

if test -z "${DMA_STATEDIR}"; then
	DMA_STATEDIR="/mnt/testarea/.${DMA_MODNAME}"
fi

if ! test -z "${DMAENG_DEBUG}"; then
	set -x
fi

dmaeng_debug ()
{
	if ! test -z "${DMAENG_DEBUG}"; then
		echo "${1} line ${2}: ${3}"
	fi
}

dmaeng_debug_state ()
{
	dmaeng_debug "${1}" "${2}" "phase: $(get_phase) config: $(get_config)"
}

# $1 - module that is being tested
dma_channel_check ()
{
	local pcibdf
	local modpci

	# Look to see if this driver was probed during boot
	if ! lsmod | grep -q "${1}"; then
		if journalctl -k | grep -qw "${1}"; then
			return 1
		else
			return 2
		fi
	fi

	# Verify that channels were created
	if ! exists /sys/class/dma/dma*chan*;
	then
		return 3
	fi

	# find channels tied to this driver
	for c in /sys/class/dma/dma*chan*; do
		pcibdf=$(readlink "$c"/device | cut -d '/' -f4)
		modpci="$(lspci -k -s ${pcibdf} | grep 'driver in us' | cut -d ' ' -f5)"
		if [ "${1}" == "${modpci}" ]; then
			if [ "$(cat ${c}/in_use)" == "0" ]; then
				dmachans+=("${c}")
			fi
		else
			echo "${DMA_TESTNAME} $(basename ${c}) (${pcibdf}) is owned by ${modpci}"
		fi
	done

	if test "${#dmachans[@]}" = "0"; then
		return 4
	fi

	return 0
}

# $1 - module being tested
driverCheck ()
{
	local failmsg=""
	local failresult=""

	dma_channel_check "${1}"
	case $? in
		0)
			return
			;;
		1)
			failmsg="${DMA_TESTNAME} There are traces of ${1} in the kernel log, but it is not loaded"
			failresult="FAIL"
			;;
		2)
			failmsg="${DMA_TESTNAME} There is no trace of ${1} ever running on the system"
			failresult="SKIP"
			;;
		3)
			failmsg="${DMA_TESTNAME} ${1} is loaded, but there are no dma channels on the system"
			failresult="FAIL"
			;;
		4)
			failmsg="${DMA_TESTNAME} All dma channels are owned by another driver"
			failresult="SKIP"
			;;
	esac

	test_complete "${DMA_TESTNAME}-driver-check" "${failresult}" "${failmsg}"
}

setup_test_env ()
{
	export CHANS=0
}

cleanup_test_env ()
{
	unset CHANS
}

setup_sys ()
{
	export dmachans=()
	modprobe -q dmatest
}

cleanup_sys ()
{
	unset dmachans
	modprobe -rq dmatest
}

# $1 - dmatest to run (0 - memcpy, 1 - memset)
# $2 - threads per channel to use
# $3 - Sub-test name
test_run ()
{

	local chan

	echo "${1}" > /sys/module/dmatest/parameters/timeout
	echo "${2}" > /sys/module/dmatest/parameters/iterations
	echo "${3}" > /sys/module/dmatest/parameters/dmatest
	echo "${4}" > /sys/module/dmatest/parameters/threads_per_chan
	for c in "${dmachans[@]}";
	do
		chan="$(basename ${c})"
		if [ "$(cat ${c}/in_use)" == "0" ]; then
			(( CHANS++ ))
			echo "${chan}" > /sys/module/dmatest/parameters/channel
		fi
	done

	# These channels were free when we started, so
	# if there are not free now something must be amiss
	if [ $CHANS -eq 0 ]; then
		test_complete "${5}-test-run" "FAIL" "dma channels are in_use when they should be free"
	fi

	echo "Running ${5} using ${DMA_MODNAME} with ${CHANS} channels and ${4} threads per channel"

	echo 1 > /sys/module/dmatest/parameters/run
}

# $1 - timeout
# $2 - iterations
# $3 - dmatest to run (0 - memcpy, 1 - memset)
# $4 - threads per channel to use
# $5 - Sub-test name
dmatest_run ()
{
	setup_test_env
	test_run "${1}" "${2}" "${3}" "${4}" "${5}"
	check_dmatest_results "${5}"
	cleanup_test_env
	echo 0 > /sys/module/dmatest/parameters/run
}

# $1 - sub-test being tested
check_dmatest_results ()
{
	local numres
	local passes

	# let the system log settle
	sleep 2

	numres=$(dmesg | grep dmatest | grep -c summary)
	passes=$(dmesg | grep dmatest | grep summary |	grep -c " 0 failures")
	check_dma_faults "${1}"
	if test "${passes}" = "${numres}"; then
		test_continue "${1}-check-dmatest-results" "PASS" "no dmatest failures found"
	else
		test_continue "${1}-check-dmatest-results" "FAIL" "dmatest expected passes: ${numres} actual passes: ${passes}"
	fi
}

init_test_pkgs ()
{
	if lsmod | grep -q dmatest; then
		modprobe -r dmatest
	else
		modules_internal_install
	fi

	if test "${DMA_MODNAME}" = "idxd"; then
		accel_config_test_install
	fi
}

accel_config_test_install ()
{
	if ! is_vendor "intel"; then
		return
	fi

	# attempt to install accel-config-test if needed
	if rpm -q --quiet accel-config-test; then
		return
	fi

	bash "${CDIR}/../../../general/include/scripts/buildroot.sh accel-config-test"

	if ! rpm -q --quiet accel-config-test; then
		acvers=$(rpm -q --queryformat="%{VERSION}" accel-config)
		acrel=$(rpm -q --queryformat="%{RELEASE}" accel-config)
		link="http://download.devel.redhat.com/brewroot/packages/accel-config/${acvers}/${acrel}/x86_64/accel-config-test-${acvers}-${acrel}.x86_64.rpm"
		dnf install -q -y "$link"
	fi

	if ! rpm -q --quiet accel-config-test; then
		grub_exit
		cleanup_state
		test_complete "${DMA_TESTNAME}-accel-config-test-install" "SKIP" "failed to install accel-config-test package"
	fi
}

# Install the kernel-modules-internal package for currently booted kernel
modules_internal_install ()
{

	local kver
	local link
	local karch
	local krel
	local kname1
	local kname2
	local kernel_ver

	kname1="kernel"
	kname2="kernel"
	kernel_ver=$(uname -r)
	karch=$(uname -m)

	# handle kernel-debug case
	if [[ "${kernel_ver}" =~ "+debug" ]]; then
		kname2="kernel-debug"
		kernel_ver=$(echo "${kernel_ver}" | sed -e 's/\+debug//g');
	elif [[ "${kernel_ver}" =~ "+rt-debug" ]]; then
		kname2="kernel-rt-debug"
		kernel_ver=$(echo "${kernel_ver}" | sed -e 's/\+rt-debug//g');
	elif [[ "${kernel_ver}" =~ "+rt" ]]; then
		kname2="kernel-rt"
		kernel_ver=$(echo "${kernel_ver}" | sed -e 's/\+rt//g');
	fi

	link="http://download.devel.redhat.com/brewroot/packages/${kname1}"
	kver=$(echo "${kernel_ver}" | cut -f1 -d'-')
	krel=$(echo "${kernel_ver}" | cut -f2 -d'-' | sed -e "s/\.$karch//g")

	if rpm -q --quiet "${kname2}-modules-internal-${kver}-${krel}"; then
		return 0
	fi

	dnf install -q -y "${kname2}-modules-internal-${kver}-${krel}"
	if rpm --quiet -q "${kname2}-modules-internal-${kver}-${krel}"; then
		return 0
	fi

	dnf install -q -y "${link}/${kver}/${krel}/${karch}/${kname2}-modules-internal-${kver}-${krel}.${karch}.rpm"

	if ! rpm --quiet -q "${kname2}-modules-internal-${kver}-${krel}"; then
		test_complete "${DMA_TESTNAME}-modules-internal-install" "SKIP" "Unable to install ${kname2}-modules-internal-${kver}-${krel}"
	fi

	return 0
}
