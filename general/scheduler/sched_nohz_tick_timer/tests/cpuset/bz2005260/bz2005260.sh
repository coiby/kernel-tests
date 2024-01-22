#!/bin/bash

# choose 4 cpus to construct the cpuset, we choose the first 4 of
# the first range of cpus.
# E.G. for '4-12,14-22,24-32' will choose the '24-32' range and choose the
# first 4 as '24-27' for cpuset. For '4,6,8,10,12,5,7,9,11' would choose the
# '4,6,8,10' as cpuset cpus.
function get_cpuset_cpus()
{
	local nr_cpuset_cpus=${1:-4}
	# this is defined in runtest.sh
	# shellcheck disable=SC2154
	if echo $isolated_cpus | grep -q '-'; then
		local range=$(echo $isolated_cpus | awk -F, '{print $1}')
		local first=$(echo $range | awk -F- '{print $1}')
		local last=$(echo $range | awk -F- '{print $2}')

		local subset_last=$((first+nr_cpuset_cpus-1))
		if ((subset_last > last)); then
			subset_last=$last
		fi
		local cpu_list=$first-$subset_last
	else
		local nr_isolated=$(echo $isolated_cpus | awk -F, '{ print NF}')
		if ((nr_isolated <= nr_cpuset_cpus)); then
			local nr_cpuset_cpus=$nr_isolated
			local starti=1
			local endi=$nr_isolated
		else
			local starti=1
			local endi=$nr_cpuset_cpus
		fi
		local cpu_list=$(echo $isolated_cpus | awk -v si=$starti -v ei=$endi -F, '{ for (i=si; i<=ei; i++) output=output""$i","} END {gsub(",$","",output); print output}')
	fi
	echo $cpu_list
}

function bz2005260()
{
	# this is defined in runtest.sh
	# shellcheck disable=SC2154
	if ((nr_cpu < 8)); then
		report_result "${FUNCNAME[0]}-nr_cpu_${nr_cpu}" SKIP
		return
	fi

	local cpulist=$(get_cpuset_cpus)

	check_cgroup_version
	cgroup_create bz2005260 cpuset
	cgroup_set bz2005260 cpuset cpuset.cpus=$cpulist
	if [ "$CGROUP_VERSION" = 1 ]; then
		cgroup_set bz2005260 cpuset cpuset.mems=$(cgroup_get / cpuset cpuset.mems)
	else
		cgroup_set bz2005260 cpuset cpuset.mems=$(cgroup_get bz2005260 cpuset cpuset.mems.effective)
	fi
	if [ $? -ne 0 ]; then
		rstrnt-report-result "${FUNCNAME[0]}_cgroup_setup" FAIL
		return 1
	fi

	# this is defined in runtest.sh
	# shellcheck disable=SC2154
	local first=$first_isolated

	rlServiceStart stalld
	set -x
	timeout 60 $CGROUP_EXEC ${FUNCNAME[0]} cpuset stress-ng --taskset $first --cpu 1 --sched fifo --sched-prio 50 -t 60 -l 99 --verbose &
	sleep 2
	local pid=$!
	$CGROUP_EXEC ${FUNCNAME[0]} cpuset taskset -c $first date &
	sleep 2
	local exec_start=$(date +%s)
	ls -l
	local exec_end=$(date +%s)
	local time=$(echo $exec_end - $exec_start | bc)
	ps -p $pid -o args | grep stress-ng && kill -9 $pid
	set +x
	systemctl status stalld
	rlServiceRestore stalld
	if ((time > 30)) || dmesg | grep 'blocked for more than'; then
		rstrnt-report-result  "cpus-stalled" "FAIL"
		return 1
	fi
}

function bz2005260_cleanup()
{
	cgroup_destroy bz2005260 cpuset
}
