#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of misc/resource-scaling-test
#   Description: Verify the sysfs entries
#   Author: Yumei Huang <yuhuang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

TEST="misc/resource-scaling-test"

sysfs_entries=(
	"/sys/class/regulator/regulator.[0-9]*/microvolts"
	"/sys/class/regulator/regulator.[0-9]*/name"
	"/sys/class/regulator/regulator.[0-9]*/num_users"
	"/sys/class/regulator/regulator.[0-9]*/requested_microamps"
	"/sys/class/regulator/regulator.[0-9]*/suspend_disk_state"
	"/sys/class/regulator/regulator.[0-9]*/suspend_mem_state"
	"/sys/class/regulator/regulator.[0-9]*/suspend_standby_state"
	"/sys/class/regulator/regulator.[0-9]*/type"
	"/sys/class/thermal/thermal_zone[0-9]*/available_policies"
	"/sys/class/thermal/thermal_zone[0-9]*/integral_cutoff"
	"/sys/class/thermal/thermal_zone[0-9]*/k_d"
	"/sys/class/thermal/thermal_zone[0-9]*/k_i"
	"/sys/class/thermal/thermal_zone[0-9]*/k_po"
	"/sys/class/thermal/thermal_zone[0-9]*/k_pu"
	"/sys/class/thermal/thermal_zone[0-9]*/mode"
	"/sys/class/thermal/thermal_zone[0-9]*/offset"
	"/sys/class/thermal/thermal_zone[0-9]*/policy"
	"/sys/class/thermal/thermal_zone[0-9]*/slope"
	"/sys/class/thermal/thermal_zone[0-9]*/sustainable_power"
	"/sys/class/thermal/thermal_zone[0-9]*/temp"
	"/sys/class/thermal/thermal_zone[0-9]*/trip_point_0_hyst"
	"/sys/class/thermal/thermal_zone[0-9]*/trip_point_0_temp"
	"/sys/class/thermal/thermal_zone[0-9]*/trip_point_0_type"
	"/sys/class/thermal/thermal_zone[0-9]*/type"
	"/sys/devices/system/cpu/cpu[0-9]*/cache/index[0-9]*/level"
	"/sys/devices/system/cpu/cpu[0-9]*/cache/index[0-9]*/shared_cpu_list"
	"/sys/devices/system/cpu/cpu[0-9]*/cache/index[0-9]*/shared_cpu_map"
	"/sys/devices/system/cpu/cpu[0-9]*/cache/index[0-9]*/type"
	"/sys/devices/system/cpu/cpu[0-9]*/cpu_capacity"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/driver/name"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/above"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/below"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/default_status"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/desc"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/disable"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/latency"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/name"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/power"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/rejected"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/residency"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/s2idle/time"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/s2idle/usage"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/time"
	"/sys/devices/system/cpu/cpu[0-9]*/cpuidle/state[0-9]*/usage"
	"/sys/devices/system/cpu/cpu[0-9]*/crash_notes"
	"/sys/devices/system/cpu/cpu[0-9]*/crash_notes_size"
	"/sys/devices/system/cpu/cpu[0-9]*/regs/identification/midr_el1"
	"/sys/devices/system/cpu/cpu[0-9]*/regs/identification/revidr_el1"
	"/sys/devices/system/cpu/cpu[0-9]*/topology/core_id"
	"/sys/devices/system/cpu/cpu[0-9]*/topology/core_siblings"
	"/sys/devices/system/cpu/cpu[0-9]*/topology/core_siblings_list"
	"/sys/devices/system/cpu/cpu[0-9]*/topology/physical_package_id"
	"/sys/devices/system/cpu/cpu[0-9]*/topology/thread_siblings"
	"/sys/devices/system/cpu/cpu[0-9]*/topology/thread_siblings_list"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/affected_cpus"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/cpuinfo_cur_freq"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/cpuinfo_max_freq"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/cpuinfo_min_freq"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/cpuinfo_transition_latency"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/related_cpus"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/scaling_available_frequencies"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/scaling_available_governors"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/scaling_cur_freq"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/scaling_driver"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/scaling_governor"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/scaling_max_freq"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/scaling_min_freq"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/scaling_setspeed"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/stats/time_in_state"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/stats/total_trans"
	"/sys/devices/system/cpu/cpufreq/policy[0-9]*/stats/trans_table"
	"/sys/devices/system/cpu/cpuidle/available_governors"
	"/sys/devices/system/cpu/cpuidle/current_driver"
	"/sys/devices/system/cpu/cpuidle/current_governor"
	"/sys/devices/system/cpu/cpuidle/current_governor_ro"
	"/sys/devices/system/cpu/kernel_max"
	"/sys/devices/system/cpu/offline"
	"/sys/devices/system/cpu/online"
	"/sys/devices/system/cpu/possible"
	"/sys/devices/system/cpu/present"
	"/sys/devices/system/cpu/smt/active"
	"/sys/devices/system/cpu/smt/control"
	"/sys/devices/system/cpu/vulnerabilities/gather_data_sampling"
	"/sys/devices/system/cpu/vulnerabilities/itlb_multihit"
	"/sys/devices/system/cpu/vulnerabilities/l1tf"
	"/sys/devices/system/cpu/vulnerabilities/mds"
	"/sys/devices/system/cpu/vulnerabilities/meltdown"
	"/sys/devices/system/cpu/vulnerabilities/mmio_stale_data"
	"/sys/devices/system/cpu/vulnerabilities/reg_file_data_sampling"
	"/sys/devices/system/cpu/vulnerabilities/retbleed"
	"/sys/devices/system/cpu/vulnerabilities/spec_store_bypass"
	"/sys/devices/system/cpu/vulnerabilities/spectre_v1"
	"/sys/devices/system/cpu/vulnerabilities/spectre_v2"
	"/sys/devices/system/cpu/vulnerabilities/srbds"
	"/sys/devices/system/cpu/vulnerabilities/tsx_async_abort")


result="PASS"
BOOT_CONFIG=/boot/config-$(uname -r)

if grep -q "CONFIG_REGULATOR_VIRTUAL_CONSUMER=[ym]" $BOOT_CONFIG; then
	echo "FAIL: Option CONFIG_REGULATOR_VIRTUAL_CONSUMER is not disabled"
	result="FAIL"
fi

if grep -q "REGULATOR_USERSPACE_CONSUMER=[ym]" $BOOT_CONFIG; then
	echo "FAIL: Option REGULATOR_USERSPACE_CONSUMER is not disabled"
	result="FAIL"
fi

for entry_pattern in "${sysfs_entries[@]}"; do
	for entry in $entry_pattern; do
		if [ -e "$entry" ]; then
			if [ "$(stat -c "%A" "$entry" | cut -c 9)" = "-" ]; then
				echo "PASS: File $entry exists and is read-only for non-root users"
			else
				echo "FAIL: File $entry exists but is NOT read-only for non-root users"
				result="FAIL"
			fi
		else
			echo "FAIL: File $entry does not exist"
			result="FAIL"
		fi
	done
done

rstrnt-report-result "${TEST}" $result
