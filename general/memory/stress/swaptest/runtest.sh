#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of swaptest
#   Description: swap to different kinds of disk targets under memory stress
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

swap_test_devices=()
swap_dev_sizes=()
swap_dev_types=()
swap_dev_mnts=()
result_names=()
run_tests=()
nr_devices=0

PMBENCH_RUNTIME=${PM_BENCH_RUNTIME:-360}
STRESS_NG_RUNTIME=${STRESS_NG_RUNTIME:-360}

# Select the partitio or disk with the largest size as test device
# First find the largest disk for the type, secondaly find the largest partition.
# Last find the largest lvm
function swap_disk_detect()
{
	local disk_type=${1:-}

	echo -e "Trying to find $disk_type blk devices in the system:"
	local detect_cmd="lsblk -b -d --output NAME,KNAME,ROTA,LOG-SEC,TYPE,SIZE,RA,DISC-GRAN,DISC-MAX,MOUNTPOINT"
	# Disk-partition-lvm
	local disk_size_map=$($detect_cmd | awk 'BEGIN {size=0;disk=""}
		$1 ~ "'$disk_type'" && $10 !~ "/boot" &&
			$5 == "disk" {if ($6>size){size=$6;disk=$2}} END{if (disk=="") exit;print disk,size}')

	detect_cmd="lsblk -b --output NAME,KNAME,ROTA,LOG-SEC,TYPE,SIZE,RA,DISC-GRAN,DISC-MAX,MOUNTPOINT"
	if [ -n "$disk_size_map" ]; then
		disk_dev=$(echo $disk_size_map | awk '{print $1}')
		part_size_mnt=$($detect_cmd /dev/$disk_dev |
			awk 'BEGIN {size=0;part=""} $1 ~ "'$disk_type'" &&
				$5 == "part" && $10 !~ "/boot" {if ($6>size){size=$6;part=$2;mnt=$10}}
						END{if(part=="") exit;print part,size,mnt}')
	else
		echo "No ${disk_type} disk is found, skip ${disk_type} disk/part/lvm topology detect"
		return
	fi

	if [ $disk_type = "nvme" ] && ! lsmod | grep nvme; then
		echo "No ${disk_type} disk is found, skip ${disk_type} disk/part/lvm topology detect"
		return
	fi

	if [ -n "$part_size_mnt" ]; then
		echo "Find $disk_type disk: $disk_size_map"
		echo "- partition: $part_size_mnt"
		# If it's mounted, use the partition directly
		local mnt=$(echo $part_size_mnt | awk '{print $3}')
		local dev=$(echo $part_size_mnt | awk '{print $1}')
		local sz=$(echo $part_size_mnt | awk '{print $2}')
		if [ -n "$mnt" ]; then
			echo "Adding $disk_type test device $dev (size:$sz mnt:$mnt)"
			swap_test_devices+=($dev)
			swap_dev_sizes+=($sz)
			swap_dev_types+=("partition_fs")
			swap_dev_mnts+=($mnt)
			result_names+=("${disk_type}_partition")
			((nr_devices++))
		else
			lvm_size_mnt=$($detect_cmd /dev/$dev | awk 'BEGIN {size=0;part=""} $5 == "lvm" &&
				$10 !~ "SWAP" {if ($6>size){size=$6;part=$1;mnt=$10}}
							END{if (part=="") exit;print part,size,mnt}')
			if [ -n "$lvm_size_mnt" ]; then
				dev=$(echo $lvm_size_mnt | awk '{gsub("/dev/", "", $1); print $1}')
				mnt=$(echo $lvm_size_mnt | awk '{print $3}')
				sz=$(echo $lvm_size_mnt | awk '{print $2}')
				echo "Adding ${disk_type} test device $dev (size:$sz mnt:$mnt)"
				swap_test_devices+=($dev)
				swap_dev_sizes+=($sz)
				swap_dev_types+=("lvm_fs")
				swap_dev_mnts+=($mnt)
				result_names+=("${disk_type}_lvm_partition")
				((nr_devices++))
			fi
		fi
	elif [ -n "$disk_size_map" ]; then
		echo "Find ${disk_type} disk: $disk_size_map"
		swap_test_devices+=($(echo $disk_size_map | awk '{print $1}'))
		swap_dev_sizes+=($(echo $disk_size_map | awk '{print $2}'))
		swap_dev_types+=("disk")
		swap_dev_mnts+=("")
		result_names+=("${disk_type}_disk")
		((nr_devices++))
	fi
	# No special runtests for nvme/sda, by default run with /home/swapfile or /swapfile
	run_tests+=("true")
}

function show_test_devices()
{
	((nr_devices == 0 )) && echo "No test devices deteced. skip test.."
	for ((i=0; i<nr_devices;i++)); do
		echo "device: dev/${swap_test_devices[$i]}"
		echo "type:   ${swap_dev_types[$i]}"
		echo "size:   ${swap_dev_sizes[$i]}"
		echo "mnt:    ${swap_dev_mnts[$i]}"
		echo "report: ${result_names[$i]}"
	done
}

function setup_nvdimm_swap()
{
	pmem_devs=$(find /dev -type b -name "pmem*" -printf "%P\n")
	size_max=0
	pmem_select=""
	size=0

	if [ -z "$pmem_devs" ]; then
		echo "No persistent memory device is found.."
		return
	fi

	if ! stat /run/ostree-booted 2&>1 ; then
		rpm -q ndctl >/dev/null 2>&1
		[ $? -ne 0 ] && yum -y install ndctl >/dev/null 2>&1
	fi

	rlRun -l "lsblk -D -t" 0 "Get block device rotation info"
	rlRun "ndctl list" -l 0 "show persistent devices"

	for pmem in $pmem_devs; do
		size=$(lsblk | grep -E "$pmem" |
			awk '{split($4, a, "M|G|T",s); if (s[1]=="T") a[1]*=1024;
				else if (s[1]=="M") a[1]/=1024; print a[1]}')
		if mount | grep $pmem; then
			echo "$pmem ($size G) is already mounted, next..."
			continue
		fi
		if ((size > size_max)); then
			echo "Use $pmem ($size G) as pmem test device"
			size_max=$size
			pmem_select=$pmem
			swap_test_devices+=("$pmem_select")
			run_tests+=("run_nvdimm_swap")
			swap_dev_sizes+=($size_max)
			swap_dev_types+=("disk")
			result_names+=("nvdimm")
			swap_dev_mnts+=("")
			((nr_devices++))
		fi
	done
}

function create_cgroup_memory()
{
	local cgroup_version=$1
	local cgroup_dir=$2
	local mem_size_max=$3 # can be format like 1g,2m,3t
	local mem_swap_max=$4 # can be format like 1g,2m,3t

	if [ "$cgroup_version" = 1 ]; then
		cgroup=$cgroup_root/memory/$cgroup_dir
		rlRun "mkdir -p $cgroup"
		rlRun "echo ${mem_size_max} > $cgroup/memory.limit_in_bytes"
		rlRun "echo ${mem_swap_max} > $cgroup/memory.memsw.limit_in_bytes"
	elif [ "$cgroup_version" = 2 ]; then
		cgroup=$cgroup_root/$cgroup_dir
		rlRun "mkdir -p $cgroup"
		rlRun "echo ${mem_size_max} > $cgroup/memory.max"
		rlRun "echo ${mem_swap_max} > $cgroup/memory.swap.max"
	fi
}

function show_memory_stat()
{
	rlRun -l "cat $cgroup/memory.stat"
	if [ "$cgroup_version" = 1 ]; then
		rlRun -l "cat $cgroup/memory.memsw.max_usage_in_bytes"
		rlRun -l "cat $cgroup/memory.max_usage_in_bytes"
	elif [ "$cgroup_version" = 2 ]; then
		rlRun -l "cat $cgroup/memory.events"
		rlRun -l "cat $cgroup/memory.swap.events"
	fi
}

cgexec=./cgexec.sh
function run_nvdimm_swap()
{
	local test_dir=nvdimm_test_$(date +%s)
	local mem_free_g=$(free -g | awk '/Mem/ {print $4}')

	# %20 physical memory
	rlRun "mkswap /dev/${swap_test_devices[$i]}"
	swapon -o pri=1,discard=pages /dev/${swap_test_devices[$i]}

	local use_mem_size=$(echo $mem_free_g \* 0.2 | bc | awk -F. '{print $1}')
	local swap_free_g=$(free -g | awk '/Swap/ {print $4}')
	local swap_mem_total=$((swap_free_g + use_mem_size))

	swapon -s | grep ${swap_test_devices[$i]} || rlDie "/dev/${swap_test_devices[$i]} not swapon"
	rlRun "swapon -s"
	rlRun -l "free -m"

	create_cgroup_memory ${cgroup_version} ${test_dir} ${use_mem_size}g ${swap_mem_total}g

	# -m mmap_size (MiB), -s workingset_size (MiB), -j nthreads, -c (no warmup)
	rlRun "$cgexec $cgroup_version $cgroup ./pmbench/pmbench -m $(echo $swap_mem_total \* 1024 | bc) -s $(echo $swap_mem_total \* 1024 | bc) -c -j $(nproc) ${PMBENCH_RUNTIME}"
	show_memory_stat

	rlRun "swapoff /dev/${swap_test_devices[$i]}"
	rlRun "rmdir $cgroup"
}

function run_swap_sress_file()
{
	echo "Running swap test in dev: ${swap_test_devices[$i]} ${swap_dev_types[$i]} ${swap_dev_mnts[$i]}"

	local opt=""
	local dev="${swap_test_devices[$i]}"
	if  [[ $dev =~ "pmem" || $dev =~ "nvme" ]]; then
		opt=",discard=pages"
	fi
	local file_size_g=4
	local file_resize_g=4
	if [ "${swap_dev_types[$i]}" = disk ]; then
		# Test with file under fs, create fs and the file
		rlRun "mkfs.xfs -f /dev/${swap_test_devices[$i]}"
		mnt_point="/mnt/${result_names[$i]}"
		mkdir -p "$mnt_point"
		rlRun "mount -t xfs /dev/${swap_test_devices[$i]} $mnt_point"
		rlRun "touch $mnt_point/swapfile"
		rlRun "dd if=/dev/zero bs=$(expr $file_size_g \* 1024 / 16)M count=16 of=$mnt_point/swapfile"
		rlRun "mkswap $mnt_point/swapfile"
		rlRun "swapon -o pri=2${opt} $mnt_point/swapfile"
		rlRun "fallocate -l $((file_resize_g))g $mnt_point/swapfile" 0-255
	elif [[ "${swap_dev_types[$i]}" =~ fs ]]; then
		mnt_point=${swap_dev_mnts[$i]}
		rlRun "touch $mnt_point/swapfile"
		rlRun "dd if=/dev/zero bs=$(expr $file_size_g \* 1024 / 16)M count=16 of=$mnt_point/swapfile"
		rlRun "mkswap $mnt_point/swapfile"
		rlRun "swapon -o pri=2${opt} $mnt_point/swapfile"
		rlRun "fallocate -l $((file_resize_g))g $mnt_point/swapfile" 0-255
	fi

	sync
	echo 3 > /proc/sys/vm/drop_caches
	free -m

	local mem_free_m=$(free -m | awk '/Mem/ {print $4}') # in MiB
	local use_mem_size=$(echo $mem_free_m \* 0.2 | bc | awk -F. '{print $1}')
	local swap_free_m=$(free -m | awk '/Swap/ {print $4}')
	local map_length=$((swap_free_m + use_mem_size)) # in MiB
	local workingset_size=${map_length}
	local workingset_no_oom=

	local cg_dir=${result_names[$i]}_file
	create_cgroup_memory "$cgroup_version" ${cg_dir} ${use_mem_size}m ${workingset_size}m

	rlRun "$cgexec $cgroup_version $cgroup timeout $((STRESS_NG_RUNTIME + 20)) stress-ng --vm $(nproc) --vm-bytes ${workingset_size}m -t ${STRESS_NG_RUNTIME}" 0-255

	test -f ./pmbench/pmbench || { skip_pmbench=1; rstrnt-report-result "pmbench_no_binary" SKIP; }
	for j in $(seq 1 5); do
		((skip_pmbench)) && break
		local probe_time=20
		rlRun "$cgexec $cgroup_version $cgroup ./pmbench/pmbench -m $map_length -s $workingset_size -c -j $(nproc) ${probe_time}" 0-255
		[ $? -ne 0 ] && workingset_size=$(echo $workingset_size \* 0.95 | bc | awk -F. '{print $1}') && continue
		workingset_no_oom=${workingset_size}
		break
	done
	((skip_pmbench)) || rlRun "$cgexec $cgroup_version $cgroup ./pmbench/pmbench -m $map_length -s ${workingset_no_oom} -c -j $(nproc) ${PMBENCH_RUNTIME}" 0-255

	show_memory_stat

	rlRun "rmdir $cgroup"

	swapoff $mnt_point/swapfile
	rm -f $mnt_point/swapfile
	if [ "${swap_dev_types[$i]}" = disk ]; then
		umount "$mnt_point"
		rmdir "$mnt_point"
	fi
}

# Run swap stress test within a cgroup
function run_swap_stress()
{
	swapoff -a

	for ((i=0; i<nr_devices; i++))
	do
		result=PASS
		rlRun "${run_tests[$i]}"
		# No runtest for this disk/partition, it's nope test, mark SKIP
		if [ "${run_tests[$i]}" = "true" ]; then
			echo "No test runner for "${swap_test_devices[$i]}" type:${swap_dev_types[$i]} mnt:${swap_dev_mnts[$i]}"
			result=SKIP
		else
			echo "Test runner:${run_tests[$i]} for "${swap_test_devices[$i]}" type:${swap_dev_types[$i]} mnt:${swap_dev_mnts[$i]}"
			dmesg | grep -E "WARNING:|BUG:|Oops" && result=FAIL
		fi

		rstrnt-report-result "${result_names[$i]}" $result

		result=PASS
		run_swap_sress_file
		dmesg | grep -E "WARNING:|BUG:|Oops" && result=FAIL && echo "Please check dmesg.log or console.log"
		rstrnt-report-result "${result_names[$i]}_file" $result
	done

	swapon -a
}

function setup()
{
	export cgroup_version=1

	if mount | grep -E "^cgroup2"; then
		cgroup_root=$(mount | awk '/cgroup2/ {print $3; exit}')
		rlRun -l "cat $cgroup_root/cgroup.controllers"
		nr_v2_controllers=$(awk '{print NF}' $cgroup_root/cgroup.controllers)
		((nr_v2_controllers > 0)) && echo "Using cgroup V2" && cgroup_version=2
	else
		cgroup_root=$(mount | grep cgroup | awk '/cgroup /{split($3, a, "cgroup"); print a[1]"cgroup"; exit}')
	fi

	# stress-ng install
	if ! which stress-ng >/dev/null 2>&1; then
		pushd  ../../../include/scripts/
		sh stress.sh
		which stress-ng || rlDie "failed to install stressor stress-ng"
		popd
	fi

	rlRun -l "cat /sys/kernel/mm/swap/vma_ra_enabled" 0 "check vma readahead enabled status"

	# pmbench install
	LOOKASIDE=${LOOKASIDE:-http://download.devel.redhat.com/qa/rhts/lookaside}
	curl -LkO $LOOKASIDE/pmbench.tar.gz
	tar -zxf pmbench.tar.gz
	if ! stat /run/ostree-booted &> /dev/null ; then
		rpm -q --quiet libxml2-devel || yum -y install libxml2-devel >/dev/null 2>&1
		rpm -q --quiet libuuid-devel || yum -y install libuuid-devel >/dev/null 2>&1
	fi

	pushd pmbench
	make
	rlRun "test -f pmbench"
	[ $? -ne 0 ] && ! uname -m | grep x86_64  && rlDile "pmbench compile failed"
	popd

	rlRun -l "lsblk" 0 "show system partitions/disk info"

	blk_cmd="lsblk -b -d --output NAME,KNAME,ROTA,LOG-SEC,TYPE,SIZE,RA,DISC-GRAN,DISC-MAX,MOUNTPOINT"
	rlRun -l "$blk_cmd" 0 "show disk rotation/size info"

	echo -e "Rotational disk devices:"
	$blk_cmd | awk '$3 == 1 {print}'
	nr_rotation_disk=$($blk_cmd | awk '$3 == 1 {print}' | wc -l)

	echo -e "\nNon rotational disk devices:"
	$blk_cmd | awk '$3 == 0 {print}'

	nr_solid_disk=$($blk_cmd | awk '$3 == 0 {print}' | wc -l)
	if uname -m | grep -q x86_64; then
		setup_nvdimm_swap
		swap_disk_detect nvme
	fi

	if ((nr_devices == 0)); then
		echo "No solid disk available (nr_rotation_disk:$nr_rotation_disk nr_solid_disk:$nr_solid_disk), selecting normal rotational disk for testing..."
		# Select the disk where /home is on.
		rotation_test_dev=$(lsblk -b -i -T | awk '$0 ~ "^[[:alpha:]]" {current_disk=$1} /home/ {print current_disk}')
		[ -z "$rotation_test_dev" ] && rotation_test_dev=$(lsblk -b -i -T | awk '$0 ~ "^[[:alpha:]]" {current_disk=$1} /root/ {print current_disk}')
		echo "Selecting $rotation_test_dev as rotational disk test dev,as /home is in $rotation_test_dev"
		[ -n "$rotation_test_dev" ] && swap_disk_detect $rotation_test_dev
	fi
	show_test_devices
}

rlJournalStart
	rlPhaseStartSetup
		setup
	rlPhaseEnd

	rlPhaseStartTest
		run_swap_stress
	rlPhaseEnd

	rlPhaseStartCleanup
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText
