#!/bin/bash

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname $FILE)
. $CDIR/../../../cki_lib/libcki.sh
. $CDIR/../../include/bash_modules/lxt/include.sh || exit 200

[ -f /root/TEST_DEVS ] && TEST_DEVS=$(cat /root/TEST_DEVS)
# shellcheck disable=SC2034
[ -f /root/TEST_DEVS_LIST ] && TEST_DEVS_LIST=$(cat /root/TEST_DEVS_LIST)

if [ -z "$TEST_DEVS" ]; then
	tlog "Abort test as no TEST_DEVS avaiable for testing"
	rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
	rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
fi

function SSD_RM_Unused_VG() {

	if rlIsRHEL 6; then
		sys_vg=$(df -h | grep -E "storageqe.*home" | awk -F'-' '{print $1}' | awk -F'/' '{print $4}')
	elif rlIsRHEL 7; then
		sys_vg=$(df -h | grep "/home" | awk -F'-home' '{print $1}' | awk -F'/' '{print $4}' | sed "s#--#-#g")
	elif rlIsRHEL ">=8"; then
		sys_vg=$(df -h | grep "/home" | awk -F'-home' '{print $1}' | awk -F'/' '{print $4}' | sed "s#--#-#g")
	elif rlIsFedora ">=25"; then
		sys_vg=$(df -h | grep "/home" | awk -F'-home' '{print $1}' | awk -F'/' '{print $4}')
	fi

	vgdisplay | grep "VG Name" | awk '{print $3}' >vg_list
	while read -r LINE
	do
		tmp_vg=$LINE
		tlog "SYS_VG:$sys_vg, TMP_VG:$tmp_vg"
		if [ "$sys_vg" != "$tmp_vg" ]; then
			vgremove -f "$tmp_vg"
			tlog "VG:$tmp_vg removed"
		fi
	done < vg_list
	rm -f vg_list
	tlog "System installed on VG:$sys_vg"
}

function SSD_RM_Unused_Partitions() {

	for test_dev in $TEST_DEVS; do
		part_num=$(cat /proc/partitions  | grep "${test_dev}." | wc -l)
		tmp_p=$part_num
		if [ "$tmp_p" -eq "0" ]; then
			tlog "${test_dev} has no partitions, continue"
			continue
		fi

		while [ "$tmp_p" -gt "1" ]
		do
fdisk /dev/"$test_dev" >/dev/null 2>&1 << EOF
d
$tmp_p
w
EOF
		((tmp_p--))
		done

		if [ "$tmp_p" -eq "1" ]; then
fdisk /dev/"$test_dev" >/dev/null 2>&1 << EOF
d
w
EOF
		fi
		tlog "deleted $part_num partitions on $test_dev"
	done
}

function get_nvme_disk() {

	DISKS="$TEST_DEVS"
	tlog "Will use $DISKS for testing"
}

function get_nvme_pci_id() {

	NVME_DISK=$1
	NVME_CHAR=${NVME_DISK:0:5}
	TEST_DEV_SYSFS=/sys/block/$NVME_DISK/device
	uname -r | grep -qE "el9|el10" && TEST_DEV_SYSFS="$TEST_DEV_SYSFS/$NVME_CHAR"
	readlink -f "$TEST_DEV_SYSFS" | \
		grep -Eo '[0-9a-f]{4,5}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]' | \
		tail -1
}

function partition_1_primary() {

	tlog "will partition for $1"
	disks="$1"
	for disk in $disks; do
fdisk /dev/"$disk" &>/dev/null <<EOF
n
p
1


w
EOF
	sleep 5
	if [[ "$disk" =~ "sd" ]]; then
		TEST_DISKS+=" ${disk}1"
	elif [[ "$disk" =~ nvme ]]; then
		TEST_DISKS+=" ${disk}p1"
	fi
done
	udevadm settle
}

function install_dt() {
	#Get dt
	trun which dt
	if [ $? -eq 0 ]; then
		tlog "dt already installed"
		return
	else
		tlog "Installing dt from https://github.com/RobinTMiller/dt.git"
		tok "git clone https://github.com/RobinTMiller/dt.git"
		tok "cd dt && make linux && cp linux.d/dt /usr/sbin/"
	fi
}

function install_fio() {

	trun which fio
	if [ $? -eq 0 ]; then
		tlog "Fio already installed"
		return
	else
		tlog "Installing fio from git://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git"
		git_url=git://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git
		tok git clone $git_url
		tok "cd fio && ./configure && make && make install"
		tlog "Fio succesfully installed from source"
	fi
}

function install_iozone() {

	trun which iozone
	if [ $? -eq 0 ]; then
		tlog "Iozone already installed"
		return
	fi
	target="linux-ia64"
	ARCH=$(arch)
	if [ "$ARCH" = "ppc64le" ]; then
		target="linux-powerpc64"
	fi
	tok "wget http://www.iozone.org/src/current/iozone3_490.tar -O iozone3_490.tar"
	tok "tar xf iozone3_490.tar"
	pushd iozone3_490/src/current/
	tok "make $target"
	tok "cp iozone /usr/bin/"
	tlog "Iozone succesfully installed"
}

function Iozone_Multi_Process_Test() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo "Usage: Iozone_6_Process_Test $test_dev"
		exit "${EX_USAGE}"
	fi
	# variable definitions
	local ret=0
	local test_dev="/dev/$1"
	local mountP="/mnt/fortest/$1"
	local process_num=6
	local file_parameter="${mountP}/iozone0.tmp ${mountP}/iozone1.tmp ${mountP}/iozone2.tmp ${mountP}/iozone3.tmp ${mountP}/iozone4.tmp ${mountP}/iozone5.tmp"
	local default_parameter="-t $process_num -F $file_parameter"

	tlog "Executing Iozone_6_Process_Test() with device: $test_dev"

	#Change the process_num and file parameters
	if [[ $2 = "mq" ]] && [[ $3 -gt 0 ]]; then
		local mq_num=$3
		process_num=$((mq_num*3))
		local num=0
		while [ "$num" -lt "$process_num" ]
		do
			tmp="$tmp $mountP/iozone${num}.tmp"
			((num++))
		done
		file_parameter="$tmp"
		default_parameter="-t $process_num -F $file_parameter"
	fi

	#which filesystem to test
	trun which mkfs.ext4
	if [ $? -eq 0 ]; then
		FILESYS="ext4"
	else
		FILESYS="ext3"
	fi

	#iozone testing
	tok mkfs -t "$FILESYS" "$test_dev"
	if [ ! -d "${mountP}" ]; then
		mkdir -p "${mountP}"
	fi
	trun mount -t "$FILESYS" "$test_dev" "$mountP"
	tlog "Executing iozone testing for $test_dev on mountP:$mountP"
	tok "iozone $default_parameter -s 10240M -r 1M -i 0 -i 1 -+d -+n -+u -x -e -w -C"
	if [ $? -ne 0 ]; then
		tlog "FAIL: Iozone_6_Process_Test for $TEST_DISK failed"
		ret=1
	fi
	trun umount -l "$test_dev"
	return $ret
}

function FIO_Device_Level_Test() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo "Usage: FIO_Device_Level_Test $test_dev"
		exit "${EX_USAGE}"
	fi
	# variable definitions
	local ret=0
	local tmp_dev=$1
	local runtime=120
	local numjobs=30
	local iodepth=1
	local t_size=1G
	#Change default numjobs, runtime and iodepth
	if [[ $2 = "mq" ]] && [[ $3 -gt 0 ]]; then
		local mq_num=$3
		numjobs=$((mq_num*5))
		iodepth=$((mq_num*5))
		runtime=180
		t_size=100G
	fi

	if [ "${tmp_dev:0:5}" = "/dev/" ]; then
		test_dev=$tmp_dev
	else
		test_dev="/dev/${tmp_dev}"

	fi
	tlog "Executing FIO_Device_Level_Test() with device: $test_dev"

	#fio testing
	tlog "Executing fio write operation"
	tok "fio -filename=$test_dev -iodepth=$iodepth -thread -rw=write -ioengine=libaio -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=$runtime -time_based -size=$t_size -group_reporting -name=mytest -numjobs=$numjobs"
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio device level write testing for $test_dev failed"
		ret=1
	fi
	tlog "Executing fio randwrite operation"
	tok "fio -filename=$test_dev -iodepth=$iodepth -thread -rw=randwrite -ioengine=libaio -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=$runtime -time_based -size=$t_size -group_reporting -name=mytest -numjobs=$numjobs"
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio device level randwrite testing for $test_dev failed"
		ret=1
	fi
	tlog "Executing fio read operation"
	tok "fio -filename=$test_dev -iodepth=$iodepth -thread -rw=read -ioengine=libaio -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=$runtime -time_based -size=$t_size -group_reporting -name=mytest -numjobs=$numjobs"
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio device level read testing for $test_dev failed"
		ret=1
	fi
	tlog "Executing fio randread operation"
	tok "fio -filename=$test_dev -iodepth=$iodepth -thread -rw=randread -ioengine=libaio -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=$runtime -time_based -size=$t_size -group_reporting -name=mytest -numjobs=$numjobs"
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio device level randread testing for $test_dev failed"
		ret=1
	fi

	return $ret
}
####################### End of functoin FIO_Device_Level_Test

function FIO_File_Level_Test() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo "Usage: FIO_Device_Level_Test $test_dev"
		exit "${EX_USAGE}"
	fi
	# variable definitions
	local ret=0
	local test_dev=$1
	local runtime=120
	local numjobs=30
	local iodepth=1
	#size G
	local t_size=1G

	#Change default numjobs, runtime and iodepth
	if [[ $2 = "mq" ]] && [[ $3 -gt 0 ]]; then
		local mq_num=$3
		numjobs=$((mq_num*5))
		iodepth=$((mq_num*5))
		runtime=180
		t_size=100G
	fi

	#fio testing
	tlog "Executing fio write operation"
	tok "fio -filename=$test_dev -iodepth=$iodepth -thread -rw=write -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=$runtime -size=$t_size -name=mytest -numjobs=$numjobs"
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio file level write testing for $test_dev failed"
		ret=1
	fi
	tlog "Executing fio randwrite operation"
	tok "fio -filename=$test_dev -iodepth=$iodepth -thread -rw=randwrite -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=$runtime -size=$t_size -name=mytest -numjobs=$numjobs"
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio file level randwrite testing for $test_dev failed"
		ret=1
	fi
	tlog "Executing fio read operation"
	tok "fio -filename=$test_dev -iodepth=$iodepth -thread -rw=read -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=$runtime -size=$t_size  -name=mytest -numjobs=$numjobs"
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio file level read testing for $test_dev failed"
		ret=1
	fi
	tlog "Executing fio randread operation"
	tok "fio -filename=$test_dev -iodepth=$iodepth -thread -rw=randread -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime=$runtime -size=$t_size  -name=mytest -numjobs=$numjobs"
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio file level randread testing for $test_dev failed"
		ret=1
	fi

	return $ret
}

function DT_IO_Test_Device_Level() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo "Usage: DT_IO_Test_Device_Level $test_dev"
		exit "${EX_USAGE}"
	fi
	# this parameter should be change to 7200 during a real testing cycle
	local ret=0
	local process_num=1
	local dt_runtime=60
	local test_dev="/dev/$1"
	local dt_logfile="/root/dt_$(date +%Y%m%d_%H%M%S)_$1.log"

	#Change default process_num and runtime
	if [[ $2 = "mq" ]] && [[ $3 -gt 0 ]]; then
		local mq_num=$3
		process_num=$((mq_num*5))
		dt_runtime=$((60*3))
	fi

	tlog "Executing DT_IO_Test_Device_Level() with device: $test_dev"
	tlog "dt against ${test_dev} is running with runtime: ${dt_runtime}s, log file is: ${dt_logfile}, process num is: $process_num"
	tlog "dt slices=16 disable=eof,pstats flags=direct oncerr=abort min=b max=256k pattern=iot iodir=reverse prefix='%d@%h (pid %p)' procs=${process_num} of=${test_dev} log=${dt_logfile} runtime=${dt_runtime}"
	tok "dt slices=16 disable=eof,pstats flags=direct oncerr=abort min=b max=256k pattern=iot iodir=reverse prefix='%d@%h (pid %p)' procs=$process_num of=${test_dev} log=${dt_logfile} runtime=${dt_runtime}"
	if [ $? -ne 0 ]; then
		tlog "Failed to run dt device level testing against $test_dev"
		ret=1
	fi
	rm -f "${dt_logfile}"-*
	return $ret
}

function DT_IO_Test_File_Level() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo "Usage: DT_IO_Test_File_Level $test_dev"
		exit "${EX_USAGE}"
	fi

	#local variable
	local ret=0
	local process_num=1
	local dt_runtime=60
	local dt_logfile="/root/dt_$(date +%Y%m%d_%H%M%S)_$1.log"
	local test_dev="/dev/$1"
	local mountP="/mnt/fortest/$1"

	#Change default process_num and runtime
	if [[ $2 = "mq" ]] && [[ $3 -gt 0 ]]; then
		local mq_num=$3
		process_num=$((mq_num*5))
		dt_runtime=$((60*3))
	fi

	tlog "Executing DT_IO_Test_File_Level() with device: $test_dev"
	#which filesystem to test
	trun which mkfs.ext4
	if [ $? -eq 0 ]; then
		FILESYS="ext4"
	else
		FILESYS="ext3"
	fi
	tok mkfs -t "$FILESYS" "$test_dev"
	if [ ! -d "${mountP}" ]; then
		mkdir -p "${mountP}"
	fi
	tok mount -t "$FILESYS" "$test_dev" "$mountP"

	#Start testing
	tlog "dt against ${test_dev} is running with runtime: ${dt_runtime}s, log file is: ${dt_logfile}, process num is: $process_num"
	tlog "dt slices=16 disable=eof,pstats dispose=keep  flags=direct oncerr=abort min=b max=256k pattern=iot iodir=reverse limit=7g procs=${process_num} runtime=$dt_runtime log=${dt_logfile} of=${mountP}/test_file"
	tok "dt slices=16 disable=eof,pstats dispose=keep  flags=direct oncerr=abort min=b max=256k pattern=iot iodir=reverse limit=7g procs=${process_num} runtime=$dt_runtime log=$dt_logfile of=${mountP}/test_file"
	if [ $? -ne 0 ]; then
		tlog "FAIL: Failed to run dt file level testing against $test_dev"
		ret=1
	fi
	tok umount -l "$test_dev"
	rm -f "${dt_logfile}"-*
	return $ret
}

function setup_os_boot_entry() {
	if efibootmgr &>/dev/null ; then
		os_boot_entry=$(efibootmgr | awk '/BootCurrent/ { print $2 }')
		# fall back to /root/EFI_BOOT_ENTRY.TXT if it exists and BootCurrent is not available
		if [[ -z "$os_boot_entry" && -f /root/EFI_BOOT_ENTRY.TXT ]] ; then
			os_boot_entry=$(</root/EFI_BOOT_ENTRY.TXT)
		fi
		if [[ -n "$os_boot_entry" ]] ; then
			tlog "efibootmgr -n $os_boot_entry"
			trun "efibootmgr -n $os_boot_entry"
		else
			tlog "Could not determine value for BootNext!"
		fi
	fi
}

setup_os_boot_entry
tok "nvme list"
