#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#  Copyright Red Hat, Inc
#
#  SPDX-License-Identifier: GPL-2.0-or-later
#
#  This script is designed to verify the configuration of various virtual memory
#  (VM) related kernel tunables. It checks if the current system settings match
#  a set of expected values defined for different architectures.
#
#  The script defines three functions:
#  - `set_arch_specific_values` to initialize architecture-dependent tunable values,
#  - `set_kernel_specific_values` to initialize kernel-specific tunable values,
#  - `check_vm_tunable` to compare the current tunable values against the expected ones,
#
#  It is intended to be used as part of a larger test suite to ensure system
#  configurations adhere to expected norms.
#
# Signed-off-by: Li Wang <liwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include beaker environment
. /usr/share/beakerlib/beakerlib.sh	|| exit 1
. ./include.sh				|| exit 1

# Declare an array 'expected_values' containing __baseline__ kernel vm tunables.
#
# These values are extracted from RHEL (Red Hat Enterprise Linux) and
# RHIVOS (Red Hat In-Vehicle Operating System), establishing a basic
# baseline for kernel parameter validation to ensure there are no
# unintended changes during testing in vehicular systems.
#
# Tunables extracted from:
# 	RHIVOS:	5.14.0-427.380.el9iv.aarch64
# 	RHEL9:  5.14.0-427.el9.aarch64
#
declare -A expected_values=(
	["dirty_ratio"]=20
	["dirty_background_ratio"]=10
	["overcommit_memory"]=0
	["overcommit_ratio"]=50
	["max_map_count"]=65530
	["swappiness"]=60
	["compact_unevictable_allowed"]=0
	["dirty_background_bytes"]=0
	["dirty_bytes"]=0
	["dirty_expire_centisecs"]=3000
	["dirtytime_expire_seconds"]=43200
	["dirty_writeback_centisecs"]=500
	["laptop_mode"]=0
	["legacy_va_layout"]=0
	["memory_failure_early_kill"]=0
	["memory_failure_recovery"]=1
	["mmap_min_addr"]=65536
	["mmap_rnd_bits"]=28
	["oom_dump_tasks"]=1
	["oom_kill_allocating_task"]=0
	["overcommit_kbytes"]=0
	["page-cluster"]=3
	["page_lock_unfairness"]=5
	["panic_on_oom"]=0
	["percpu_pagelist_high_fraction"]=0
	["stat_interval"]=1
	["vfs_cache_pressure"]=100
	["watermark_boost_factor"]=15000
	["watermark_scale_factor"]=10
	["oom_score_adj"]=0
)

# set_arch_specific_values: Set architecture-specific kernel tunable values
#
# This function sets expected values for various kernel tunables based on
# the architecture of the system. It uses an associative array `expected_values`
# to store the tunable parameters for different architectures.
#
function set_arch_specific_values()
{
	is_rhivos && return

	is_rhel && {
		rlLOG "Adding RHEL-Only tunables: hugetlb_shm_group, min_slab_ratio, min_unmapped_ratio, nr_hugepages, nr_hugepages_mempolicy, \
		nr_overcommit_hugepages, numa_stat, unprivileged_userfaultfd, zone_reclaim_mode"

		expected_values["hugetlb_shm_group"]=0
		expected_values["min_slab_ratio"]=5
		expected_values["min_unmapped_ratio"]=1
		expected_values["nr_hugepages"]=0
		expected_values["nr_hugepages_mempolicy"]=0
		expected_values["nr_overcommit_hugepages"]=0
		expected_values["numa_stat"]=1
		expected_values["unprivileged_userfaultfd"]=0
		expected_values["zone_reclaim_mode"]=0
	}

	ARCH="$(uname -m)"

	case ${ARCH} in
	aarch64)
		expected_values["mmap_rnd_bits"]=18
		expected_values["compact_unevictable_allowed"]=1
		;;
	x86_64)
		expected_values["mmap_min_addr"]=65536
		expected_values["compact_unevictable_allowed"]=1
		;;
	ppc64le)
		expected_values["mmap_rnd_bits"]=14
		expected_values["mmap_min_addr"]=4096
		expected_values["compact_unevictable_allowed"]=1
		;;
	s390x)
		expected_values["mmap_min_addr"]=4096
		expected_values["compact_unevictable_allowed"]=1
		# shellcheck disable=SC2184
		unset expected_values["mmap_rnd_bits"]
		# shellcheck disable=SC2184
		unset expected_values["memory_failure_early_kill"]
		# shellcheck disable=SC2184
		unset expected_values["memory_failure_recovery"]
		;;
	*)
		echo "Unknown architecture: ${ARCH}"
		return
		;;
	esac

	rlLog "Set tunable: mmap_rnd_bits = ${expected_values["mmap_rnd_bits"]}"
	rlLog "Set tunable: mmap_min_addr = ${expected_values["mmap_min_addr"]}"
	rlLog "Set tunable: compact_unevictable_allowed = ${expected_values["compact_unevictable_allowed"]}"
}

# This function is intended to set kernel-specific tunable values.
# Currently, it is a placeholder and does not contain any implementation.
# If certain kernel versions or specific kernel configurations require
# different settings for the tunables, this function would be the place
# to apply those settings.
#
# For example, it could be used to adjust the `expected_values` associative
# array with values that are optimal or necessary for the running kernel.
# This function should be modified to include conditional checks and
# assignments based on the kernel version or other kernel-specific criteria.
#
function set_kernel_specific_values()
{
	echo "Reserve set_kernel_specific_values function for extension"

	# define tunables value on fixed-kernel version:
	#
	# kernel_in_range "5.14.0-427.el9" "5.14.0-999.el9" && {
	#	expected_values["mmap_rnd_bits"]=14
	#	expected_values["mmap_min_addr"]=4096
	#	expected_values["compact_unevictable_allowed"]=1
	# }
}

function check_vm_tunable()
{
	local current_value
	local expected_value

	rlLog "Checking VM-related kernel tunables against expected values:"

	for tunable in "${!expected_values[@]}"; do
		if [ "$tunable" = "oom_score_adj" ]; then
			current_value=$(cat "/proc/$$/oom_score_adj" 2>/dev/null)
		else
			current_value=$(cat "/proc/sys/vm/$tunable" 2>/dev/null)
		fi

		expected_value=${expected_values[$tunable]}

		if [ -z "$current_value" ]; then
			rlFail "Tunable $tunable does not exist on this system."
			continue
		fi

		echo -n "$tunable = $current_value "
		if [ "$current_value" -eq "$expected_value" ]; then
			rlPass "$tunable expected: $expected_value, matches expected value!"
		else
			rlFail "$tunable expected: $expected_value, but got: $current_value!"
		fi
	done
}

# ---------- Start Test -------------
rlJournalStart

rlPhaseStartSetup
	if rlIsRHELLike "<=8" || rlIsFedora; then
		rlLogInfo "vm-tunables-validation is only designed for rhel9 and later"
		report_result Test_Skipped PASS 99
		exit 0
	fi
	set_arch_specific_values
	set_kernel_specific_values
rlPhaseEnd

rlPhaseStartTest
	check_vm_tunable
rlPhaseEnd

rlJournalPrintText
rlJournalEnd
