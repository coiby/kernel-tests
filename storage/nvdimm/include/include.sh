#!/bin/bash

FILE="$(readlink -f "${BASH_SOURCE[0]}")"
CDIR=$(dirname "$FILE")
. "$CDIR"/../../../cki_lib/libcki.sh
. "$CDIR"/../../include/bash_modules/lxt/include.sh || exit 200

trun "rpm -q redhat-rpm-config gcc gcc-c++ git wget ndctl || yum -y install redhat-rpm-config gcc gcc-c++ git wget ndctl"

# shellcheck disable=SC2034
SECTOR_SIZE_LIST="512 4096"

if [[ $(arch) == "ppc64le" ]]; then
# shellcheck disable=SC2034
	ext4_param="-b 65536"
# shellcheck disable=SC2034
	xfs_param="-s size=512 -b size=65536"
	devdax_align="64k 2m"
else
# shellcheck disable=SC2034
	devdax_align="4k 2m 1g"
fi

function FIO_ENGINE_SUPPORT()
{
	local ioengine=$1
	if ! fio --enghelp | grep -q "$ioengine"; then
	        tlog "INFO: fio lacks $ioengine engine"
	        return 77
	fi
	return 0
}

function NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 2 ]; then
		echo 'Usage: NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX $num (RAW|BTT|FSDAX|DEVDAX) $sector|align_size'
		exit "${EX_USAGE}"
	fi
	# variable definitions
	RETURN_STR=''
	disks=()
	local dev_num=$1
	local device_type=$2
	local s_a_size=$3
	local total_pmems=4

	tlog "INFO: Executing NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX() to get $dev_num $device_type $s_a_size device"
	if [ $dev_num -gt $total_pmems ]; then
		tlog "FAIL: Required $dev_num $device_type devices more than $total_pmems"
		exit 1
	fi

	# Clean up namespaces
	tok ndctl destroy-namespace all -r all -f

	# get RAW|BTT|FSDAX|DEVDAX list
	region_num=`ndctl list -R | grep -o "region.*[0-9]" | wc -l`
	if [ $region_num -gt 0 ]; then
		for((i=0;i<${region_num};i++)); do
			((tmp=$i+1))
			region_list[i]=`ndctl list -R | grep -o "region.*[0-9]" | head -$tmp | tail -1`
		done
	else
		tlog "INFO: no region avaiable, exit"
		exit 1
	fi

	# update region_list when region_num<4 and dev_num=4
	if [ $region_num -lt 4 -a $dev_num -eq 4 ]; then
		if [ $region_num -eq 1 ]; then
			region_list_tmp=(${region_list[0]} ${region_list[0]} ${region_list[0]} ${region_list[0]})
		elif [ $region_num -eq 2 ]; then
			region_list_tmp=(${region_list[0]} ${region_list[1]} ${region_list[0]} ${region_list[1]})
		elif [ $region_num -eq 3 ]; then
			region_list_tmp=(${region_list[0]} ${region_list[1]} ${region_list[2]} ${region_list[1]})
		fi
		region_list=(${region_list_tmp[*]})
	fi

	hn=$(hostname -s)
	hpe_nvdimm_n="hpe-dl380gen9"
	st31_nvdimm_n="storageqe-31"
	# shellcheck disable=SC2034
	st36_dcpmm="storageqe-36"
	intel_aep_02_dcpmm="intel-purley-aep-02"
	p9_nvdimm="ibm-p9z-30"
	if [[ "$hn" =~ "$hpe_nvdimm_n"|"$p9_nvdimm" ]]; then
		for((i=0;i<${dev_num};i++)); do
			if [[ "$device_type" = "RAW" ]]; then
				tlog "INFO: will create raw device on namespace$i.0"
				tok "ndctl create-namespace -f -e namespace$i.0 -m raw | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "pmem.*[0-9]"`
			elif [ "$device_type" = "BTT" -a "$s_a_size" != "" ]; then
				tlog "INFO: will create btt:$s_a_size device on namespace$i.0"
				tok "ndctl create-namespace -f -e namespace$i.0 -m sector -l $s_a_size | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "pmem.*[0-9]s"`
			elif [[ "$device_type" = "FSDAX" ]]; then
				tlog "INFO: will create fsdax device on namespace$i.0"
				tok "ndctl create-namespace -f -e namespace$i.0 -m fsdax | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "pmem.*[0-9]"`
			elif [ "$device_type" = "DEVDAX" -a "$s_a_size" != "" ]; then
				tlog "INFO: will create devdax:$s_a_size device on namespace$i.0"
				tok "ndctl create-namespace -f -e namespace$i.0 -m devdax -a $s_a_size | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "dax.*[0-9]"`
			fi
			if [ "${disks[$i]}" = "" ]; then
				tlog "INFO: get the $i $device_type failed"
				exit 1
			fi
		done
	elif [[ "$hn" =~ $st31_nvdimm_n ]]; then
		for((i=0;i<${dev_num};i++)); do
			if [[ "$device_type" = "RAW" ]]; then
				tlog "INFO: will create raw device on region$i"
				tok "ndctl create-namespace -r region$i -m raw | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "pmem.*[0-9]"`
			elif [ "$device_type" = "BTT" -a "$s_a_size" != "" ]; then
				tlog "INFO: will create btt:$s_a_size device on region$i"
				tok "ndctl create-namespace -r region$i -m sector -l $s_a_size -s 12G | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "pmem.*[0-9]s"`
			elif [[ "$device_type" = "FSDAX" ]]; then
				tlog "INFO: will create fsdax device on region$i"
				tok "ndctl create-namespace -r region$i -m fsdax -s 12G | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "pmem.*[0-9]"`
			elif [ "$device_type" = "DEVDAX" -a "$s_a_size" != "" ]; then
				tlog "INFO: will create devdax:$s_a_size device on region$i"
				tok "ndctl create-namespace -r region$i -m devdax -a $s_a_size -s 12G | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "dax.*[0-9]"`
			fi
			if [ "${disks[$i]}" = "" ]; then
				tlog "INFO: get the $i $device_type failed"
				exit 1
			fi
		done
	else
		SIZE=16G
		if [[ "$hn" =~ "intel-cedarisland-03" ]]; then
			SIZE=12G
		elif [[ "$hn" = "$intel_aep_02_dcpmm" ]]; then
			SIZE=18G
		fi
		for((i=0;i<${dev_num};i++)); do
			region=${region_list[0]}
			if [[ "$device_type" = "RAW" ]]; then
				tlog "INFO: will create raw device on $region"
				tok "ndctl create-namespace -r $region -m raw -s $SIZE | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "pmem.*[0-9]"`
			elif [ "$device_type" = "BTT" -a "$s_a_size" != "" ]; then
				tlog "INFO: will create btt:$s_a_size device on $region"
				tok "ndctl create-namespace -r $region -m sector -l $s_a_size -s $SIZE | tee OUTPUT"
				disks[$i]=` cat OUTPUT | grep -o "pmem.*[0-9]s"`
			elif [[ "$device_type" = "FSDAX" ]]; then
				tlog "INFO: will create fsdax device on $region"
				tok "ndctl create-namespace -r $region -m fsdax -s $SIZE  | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "pmem.*[0-9]"`
			elif [ "$device_type" = "DEVDAX" -a "$s_a_size" != "" ]; then
				tlog "INFO: will create devdax:$s_a_size device on $region"
				tok "ndctl create-namespace -r $region -m devdax -a $s_a_size -s $SIZE | tee OUTPUT"
				disks[$i]=`cat OUTPUT | grep -o "dax.*[0-9]"`
			fi
			if [ "${disks[$i]}" = "" ]; then
				tlog "INFO: get the $i $device_type failed"
				exit 1
			fi
		done
	fi

	# define global variables
	RETURN_STR="${disks[*]}"
	if [ $dev_num -eq $i ]; then
		tlog "INFO: Get $dev_num $device_type device: $RETURN_STR"
	fi
}
####################### End of functoin NVDIMM_Get_RAW_BTT_FSDAX_DEVDAX

function Iozone_6_Process_Test() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo 'Usage: Iozone_6_Process_Test $test_dev'
		exit "${EX_USAGE}"
	fi

	# variable definitions
	local ret=0
	local test_dev="/dev/$1"
	local mountP="/mnt/fortest"
	tlog "INFO: Executing Iozone_6_Process_Test() with device: $test_dev"

	#which filesystem to test
	trun which mkfs.xfs
	if [ $? -eq 0 ]; then
		FILESYS="xfs -f"
	else
		FILESYS="ext3"
	fi

	#iozone testing
	tok mkfs -t $FILESYS $test_dev
	if [ ! -d ${mountP} ]; then
		mkdir ${mountP}
	fi
	trun mount -t $FILESYS $test_dev $mountP
	tlog "INFO: Executing iozone testing for $test_dev on mountP:$mountP"
	tok "iozone -t 6 -F ${mountP}/iozone0.tmp ${mountP}/iozone1.tmp ${mountP}/iozone2.tmp ${mountP}/iozone3.tmp ${mountP}/iozone4.tmp ${mountP}/iozone5.tmp -s 1024M -r 1M -i 0 -i 1 -+d -+n -+u -x -e -w -C"
	if [ $? -ne 0 ]; then
		tlog "FAIL: iozone testing for $test_dev failed"
		 ret=1
	fi
	trun umount -l $test_dev

	return $ret
}
####################### End of functoin Iozone_6_Process_Test

function FIO_Device_Level_Test() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo 'Usage: FIO_Device_Level_Test $test_dev'
		exit "${EX_USAGE}"
	fi
	# variable definitions
	local ret=0
	local tmp_dev=$1
	local runtime=1200
	local numjobs=60
	local runtime=60
	local numjobs=60
	if [ "${tmp_dev:0:5}" = "/dev/" ]; then
		test_dev=$tmp_dev
	else
		test_dev="/dev/${tmp_dev}"

	fi
	tlog "INFO: Executing FIO_Device_Level_Test() with device: $test_dev"

	#fio testing
	tok fio -filename=$test_dev -iodepth=1 -thread -rw=write -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -bs_unaligned -runtime=$runtime -time_based -size=1G -group_reporting -name=mytest -numjobs=$numjobs
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio device level write testing for $test_dev failed"
		ret=1
	fi
	tok fio -filename=$test_dev -iodepth=1 -thread -rw=randwrite -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -bs_unaligned -runtime=$runtime -time_based -size=1G -group_reporting -name=mytest -numjobs=$numjobs
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio device level randwrite testing for $test_dev failed"
		ret=1
	fi
	tok fio -filename=$test_dev -iodepth=1 -thread -rw=read -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -bs_unaligned -runtime=$runtime -time_based -size=1G -group_reporting -name=mytest -numjobs=$numjobs
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio device level read testing for $test_dev failed"
		ret=1
	fi
	tok fio -filename=$test_dev -iodepth=1 -thread -rw=randread -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -bs_unaligned -runtime=$runtime -time_based -size=1G -group_reporting -name=mytest -numjobs=$numjobs
	if [ $? -ne 0 ]; then
		tlog "FAIL: fio device level randread testing for $test_dev failed"
		ret=1
	fi

	return $ret
}
####################### End of functoin FIO_Device_Level_Test

function DT_IO_Test_Device_Level() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo 'Usage: DT_IO_Test_Device_Level $test_dev'
		exit "${EX_USAGE}"
	fi
	# this parameter should be change to 7200 during a real testing cycle
	local dt_runtime=30
	local ret=0
	local dt_logfile="/root/dt_$(date +%Y%m%d_%H%M%S).log"
	local test_dev="/dev/$1"
	tlog "INFO: Executing DT_IO_Test_Device_Level() with device: $test_dev"
	tlog "INFO: dt against ${test_dev} is running with runtime: ${dt_runtime}s, log file is: ${dt_logfile}"
	tlog "INFO: dt slices=16 disable=eof,pstats flags=direct oncerr=abort min=b max=256k pattern=iot iodir=reverse prefix='%d@%h (pid %p)' of=${test_dev} log=${dt_logfile} runtime=${dt_runtime}"
	tok "dt slices=16 disable=eof,pstats flags=direct oncerr=abort min=b max=256k pattern=iot iodir=reverse prefix='%d@%h (pid %p)' of=${test_dev} log=${dt_logfile} runtime=${dt_runtime}"
	if [ $? -ne 0 ]; then
		tlog "Failed to run dt device level testing against $test_dev"
		ret=1
	fi
	return $ret
}
####################### End of functoin DT_IO_Test_Device_Level

function DT_IO_Test_File_Level (){
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo 'Usage: DT_IO_Test_File_Level $test_dev'
		exit "${EX_USAGE}"
	fi

	#local variable
	local ret=0
#	local dt_runtime=$((60 * 60 * 24))
	local dt_runtime=60
	local dt_logfile="/root/dt_$(date +%Y%m%d_%H%M%S).log"
	local test_dev="/dev/$1"
	local mountP="/mnt/fortest"

	tlog "INFO: Executing DT_IO_Test_File_Level() with device: $test_dev"
	#which filesystem to test
	trun which mkfs.ext4
	if [ $? -eq 0 ]; then
		FILESYS="ext4"
	else
		FILESYS="ext3"
	fi
	tok mkfs -t $FILESYS $test_dev
	if [ ! -d ${mountP} ]; then
		mkdir ${mountP}
	fi
	tok mount -t $FILESYS $test_dev $mountP

	#Start testing
	tlog "INFO: dt against ${test_dev} is running with runtime: ${dt_runtime}s, log file is: ${dt_logfile}"
	tlog "INFO: dt slices=16 disable=eof,pstats dispose=keep  flags=direct oncerr=abort min=b max=256k pattern=iot iodir=reverse  limit=7g  runtime=$dt_runtime log=${dt_logfile} of=${mountP}/test_file"
	tok "dt slices=16 disable=eof,pstats dispose=keep  flags=direct oncerr=abort min=b max=256k pattern=iot iodir=reverse  limit=7g  runtime=$dt_runtime log=$dt_logfile of=${mountP}/test_file"
	if [ $? -ne 0 ]; then
		tlog "FAIL: Failed to run dt file level testing against $test_dev"
		ret=1
	fi
	tok umount -l $test_dev
	return $ret
}
####################### End of functoin DT_IO_Test_Device_Level

function install_iozone() {

	trun which iozone
	if [ $? -eq 0 ]; then
		tlog "INFO: Iozone already installed"
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
	popd
	tok which iozone
	if [ $? -ne 0 ]; then
	        tlog "INFO: Iozone install failed"
		exit 1
	fi
	tlog "INFO: Izone succesfully installed"
}

function install_fio() {

	trun which fio
	if [ $? -eq 0 ]; then
		tlog "Fio already installed"
		return
	fi

	if rlIsRHEL 9; then
		trun "yum -y install fio-engine-pmemblk fio-engine-dev-dax fio-engine-libpmem libpmem-devel libpmemblk-devel --skip-broken"
	else
		trun "yum -y module enable pmdk"
		tok "yum -y install libaio-devel zlib-devel libpmem* daxio --skip-broken"
	fi

	git_url=git://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git

	if rlIsRHEL 7; then
		tok git clone -b fio-3.20 $git_url
	else
		tok git clone -b fio-3.33 $git_url
	fi
	tlog "Installing Fio"
	tok "cd fio && ./configure && make && make install"

	tlog "INFO: Fio succesfully installed"
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

#----------------------------------------------------------------------------#
# MD_Create_RAID ()
# Usage:
#   Create md raid.
# Parameter:
# 	$level				# like 0, 1, 3, 5, 10, 50
# 	$dev_list			# like 'sda sdb sdc sdd'
# 	$raid_dev_num		# like 3
# 	$spar_dev_num		# like 2
# 	$chunk				# like 64
# Returns:
#   Return code:
#       0 on success
#       1 if something went wrong.
#   Return string:
#       RETURN_STR		# $md_raid like '/dev/md0'
#		MD_DEVS			# $raid_dev_list like '/dev/sda /dev/sdb'
#----------------------------------------------------------------------------#

function MD_Create_RAID (){
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 3 ]; then
		echo 'Usage: MD_Create_RAID $level $dev_list $raid_dev_num \
		[$spar_dev_num] [$chunk]'
		exit "${EX_USAGE}"
	fi
	# variable definitions
	RETURN_STR=''
	MD_DEVS=''
	local level=$1
	local dev_list=$2
	local raid_dev_num=$3
	local bitmap=$4
	local spar_dev_num=${5:-0}
	local chunk=${6:-512}
	local bitmap_chunksize=${7:-64M}
	local dev_num=0
	local raid_dev=''
	local spar_dev=''
	local md_raid=""
	local mtdata=1.2
	local ret=0
	# start to create
	echo "INFO: Executing MD_Create_RAID() to create raid $level"
	# check if the given disks are more the needed
	for i in $dev_list; do
		dev_num=$((dev_num+1))
	done
	if [ $dev_num -lt $(($raid_dev_num+$spar_dev_num)) ]; then
		echo "FAIL: Required devices are more than given."
		exit 1
	fi
	# get free md device name, only scan /dev/md[0-15].
	for i in `seq 0 15`; do
		ls -l /dev/md$i > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			md_raid=/dev/md$i
			break
		fi
	done
	# get raid disk list.
	for i in `seq 1 $raid_dev_num`; do
		tmp_dev=`echo $dev_list | cut -d " " -f $i`
		raid_dev="$raid_dev /dev/$tmp_dev"
	done
	echo "INFO: Created md raid with these raid devices \"$raid_dev\"."
	# get spare disk list.
	if [ $spar_dev_num -ne 0 ]; then
		for i in `seq $((raid_dev_num+1)) $((raid_dev_num+spar_dev_num))`; do
			tmp_dev=`echo $dev_list | cut -d " " -f $i`
			spar_dev="$spar_dev /dev/$tmp_dev"
		done
		echo "INFO: Created md raid with these spare disks \"$spar_dev\"."
	fi

	# create md raid
	# prepare the parameter
	BITMAP=""
	SPAR_DEV=""
	CHUNK=""
	if [ $bitmap -eq 1 ]; then
		BITMAP="--bitmap=internal --bitmap-chunk=$bitmap_chunksize"
	fi
	if [ $spar_dev_num -ne 0 ]; then
		SPAR_DEV="--spare-devices $spar_dev_num $spar_dev"
	fi
	if [ $level -ne 1 ]; then
		CHUNK="--chunk $chunk"
	fi
	trun "mdadm -Ss"
	tok "mdadm --create --run $md_raid --level $level --metadata $mtdata --raid-devices $raid_dev_num $raid_dev $SPAR_DEV $BITMAP $CHUNK"
	ret=$?

	# define global variables
	MD_DEVS="$raid_dev $spar_dev"
	RETURN_STR="$md_raid"
	return $ret
}
####################### End of functoin MD_Create_RAID

#----------------------------------------------------------------------------#
# MD_Save_RAID ()
# Usage:
#   Save md raid configuration.
# Parameter:
# 	NULL
# Returns:
#   Return code:
#       0 on success
#       1 if something went wrong.
#   Return string:
#       NULL
#----------------------------------------------------------------------------#

function MD_Save_RAID (){
	echo "INFO: Executing MD_Save_RAID()"
	echo "DEVICE $MD_DEVS" > /etc/mdadm.conf
	tok "mdadm --detail --scan >> /etc/mdadm.conf"
	if [ $? -ne 0 ]; then
		echo "FAIL: Failed to save md state info to /etc/mdadm.conf"
	fi
	return 0
}
####################### End of functoin MD_Save_RAID

#----------------------------------------------------------------------------#
# MD_Clean_RAID ()
# Usage:
#	Clean md raid.
# Parameter:
#   $md_name		# like '/dev/md0'
# Returns:
#   Return code:
#       0 on success
#       1 if something went wrong.
#   Return string:
#       NULL
#----------------------------------------------------------------------------#

function MD_Clean_RAID (){
	EX_USAGE=64 # Bad arg format
	if [ $# -ne 1 ]; then
		echo 'Usage: MD_Clean_RAID $md_name'
		exit "${EX_USAGE}"
	fi
	tlog "INFO: Executing MD_Clean_RAID() against this md device: $md_name"
	local md_name=$1
	tlog "mdadm --stop $md_name"
	tok "mdadm --stop $md_name"
	if [ $? -ne 0 ]; then
		echo "FAIL: Failed to stop $md_name"
		exit 1
	fi
	tlog "clean devs : $MD_DEVS"
	for dev in $MD_DEVS; do
		echo "mdadm --zero-superblock $dev"
		tok "mdadm --zero-superblock $dev"
	done
	#`mdadm --zero-superblock "$MD_DEVS"`
	echo "ret is $?"
	rm -rf /etc/mdadm.conf
	rm -rf $md_name
	return 0
}
####################### End of functoin MD_Clean_RAID

#----------------------------------------------------------------------------#
# MD_Get_State_RAID ()
# Usage:
#   get md raid status
# Parameter:
#   $md_name		# like "/dev/md0"
# Returns:
#   Return code:
#       0 on success
#       1 if something went wrong.
#   Return string:
#       RETURN_STR  # $state, like 'clean, resyncing'
#----------------------------------------------------------------------------#

function MD_Get_State_RAID (){
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo 'Usage: MD_Get_State_RAID $md_name'
		exit "${EX_USAGE}"
	fi

	RETURN_STR=''
	local md_name=$1
	local state=''
	echo "INFO: Executing MD_Get_State_RAID() against this md array: $md_name"
	echo "mdadm --detail $md_name | grep "State :" | cut -d ":" -f 2 | cut -d " " -f 2"
	state=`mdadm --detail $md_name | grep "State :" | cut -d ":" -f 2 | cut -d " " -f 2`
	echo "state is $state"
	if [ -z "$state" ]; then
		echo "FAIL: Failed to get $md_name status"
		exit 1
	fi
	RETURN_STR="$state"
	return 0
}
####################### End of functoin MD_Get_State_RAID


#----------------------------------------------------------------------------#
# MD_IO_Test ()
# Usage:
#   IO test using dt against block level
# Parameter:
#   $dt_target		# like "/dev/md0"
# Returns:
#   Return code:
#       0 on success
#       1 if something went wrong.
#   Return string:
#		NULL
#----------------------------------------------------------------------------#

function MD_IO_Test (){
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo 'Usage: MD_IO_Test $dt_target'
		exit "${EX_USAGE}"
	fi
	# this parameter should be change to 7200 during a real testing cycle
	local dt_target=$1
	local dt_runtime=72
	local dt_logfile=""
	test -f /tmp/dt_XXXXXXXX.log || mktemp /tmp/dt_XXXXXXXX.log
	dt_logfile="/tmp/dt_XXXXXXXX.log"
	echo -n "INFO: dt against ${dt_target} is running with "
	echo "runtime: ${dt_runtime}s, log file is: ${dt_logfile}"
	echo "dt  slices=16 disable=eof,pstats flags=direct \
	oncerr=abort min=b max=256k \
	pattern=iot iodir=reverse prefix='%d@%h (pid %p)' \
	of=${dt_target} log=${dt_logfile} \
	runtime=${dt_runtime}"
	dt  slices=16 disable=eof,pstats flags=direct \
	oncerr=abort min=b max=256k \
	pattern=iot iodir=reverse prefix='%d@%h (pid %p)' \
	of=${dt_target} log=${dt_logfile} \
	runtime=${dt_runtime}
	if [ $? -ne 0 ]; then
		echo "FAIL: Failed to run dt testing against $dt_target"
		exit 1
	fi
	return 0
}
####################### End of functoin MD_IO_Test

function create_loop_devices (){
	Create_Loop_Devices "$@"
}

# ---------------------------------------------------------#
# Create_Loop_Devices ()
# Usage:
#   Create loop devices. We will find out the free number
#   of loop to bind on tmp file.
# Parameter:
#   $count      #like "12"
#   $size_mib   #like "1024"
# Returns:
#   Return code:
#       0 on success
#       1 if something went wrong.
#   Return string:
#       RETURN_STR like 'loop9 loop10'
# ---------------------------------------------------------#

function Create_Loop_Devices (){
	EX_USAGE=64 # Bad arg format
	if [ $# -ne 2 ]; then
		echo 'Usage: Create_Loop_Devices $count $size_mib'
		exit "${EX_USAGE}"
	fi
	RETURN_STR=''
	local count="$1"
	local size_mib="$2"
	local loop_dev_list=''
	# shellcheck disable=SC2034
	for X in `seq 1 ${count}`;do
		local loop_file_name=$(mktemp /opt/loop.XXXXXX)
		#dd if=/dev/zero of=${loop_file_name} count=$size_mib  bs=1M 1>/dev/null 2>&1
		fallocate -l  $((size_mib * 1024 * 1024)) ${loop_file_name} 1>/dev/null 2>&1
		local loop_dev_name=$(losetup -f)
		#BUG: RHEL5 only support 8 loop device and we need to check whether we are run out of it
		local command="losetup ${loop_dev_name} ${loop_file_name} 1>/dev/null 2>&1"
		eval "${command}"
		if [ $? -eq 0 ];then
			loop_dev_list="${loop_dev_list}${loop_dev_name} "
		else
			echo "FAIL: Failed to create loop devices with command: ${command}"
			return 1
		fi
	done
	loop_dev_list=$(echo "${loop_dev_list}" | sed -e 's/ $//')
	echo "${loop_dev_list}" #Back capability
	loop_dev_list=$(echo "${loop_dev_list}" | sed -e 's/\/dev\///g')
	RETURN_STR="${loop_dev_list}"
	return 0
}
