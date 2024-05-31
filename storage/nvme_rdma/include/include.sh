#!/bin/bash

FILE=$(readlink -f "${BASH_SOURCE[0]}")
DIR=$(dirname "$FILE")
. "$DIR"/../../../cki_lib/libcki.sh
. "$DIR"/../../include/bash_modules/lxt/include.sh || exit 200

modprobe nvmet-rdma
modprobe nvme-rdma

# export NETAPP E5700 configuration
# shellcheck disable=SC1091
[ -f "/root/NVME_RDMA_NETAPPE5700_ENV" ] && . /root/NVME_RDMA_NETAPPE5700_ENV

if [ -f "/root/NVME_RDMA_Protocol" ]; then
	test_protocol=$(cat /root/NVME_RDMA_Protocol)
	tlog "nvmeof rdma testing protocol is $test_protocol"
else
	tlog "INFO: nvmeof rdma protocol defined file /root/NVME_RDMA_Protocol doesn't exist"
	exit 1
fi

# Arguments: module to unload ($1) and retry count ($2).
unload_module() {
	local i m=$1 rc=${2:-5}

	[ ! -e "/sys/module/$m" ] && return 0
	for ((i=rc;i>0;i--)); do
		modprobe -r "$m"
		[ ! -e "/sys/module/$m" ] && return 0
		sleep .1
	done
	return 1
}

load_module()
{
	local m=$1

	[ -e "/sys/module/$m" ] || modprobe "$m"
}

unload_modules()
{
	local m

	for m in "$@"; do
		unload_module "$m"
	done
}

load_modules()
{
	local m

	for m in "$@"; do
		load_module "$m"
	done
}

function nvme_core_multipath_conf
{
	tlog "INFO: start to $1 nvme native multipath"
	if [ "$1" = "enable" ]; then
		tlog "INFO: start to unload: nvme_rdma nvme_fabrics nvme nvme_core"
		unload_modules nvme_rdma nvme_fabrics nvme nvme_core
		echo "options nvme_core multipath=Y"  > /etc/modprobe.d/nvme.conf
		tlog "INFO: start to load: nvme_rdma nvme"
		load_modules nvme_rdma nvme
		sleep 5
	elif [ "$1" = "disable" ]; then
		tlog "INFO: start to unload: nvme_rdma nvme_fabrics nvme nvme_core"
		unload_modules nvme_rdma nvme_fabrics nvme nvme_core
		echo "options nvme_core multipath=N"  > /etc/modprobe.d/nvme.conf
		tlog "INFO: start to load: nvme_rdma nvme"
		load_modules nvme_rdma nvme
	fi
	tok sleep 5
}

# disable nvme_core multipath for RHEL9/10
if rlIsRHEL 9 || rlIsRHEL 10; then
	if [ ! -f /etc/modprobe.d/nvme.conf ]; then
		nvme_core_multipath_conf disable
	fi

fi

function dm_multipath_conf
{
	tlog "INFO: start to $1 dm-multipath"
	if [ "$1" = "enable" ]; then
		rpm -q device-mapper-multipath || yum -y install device-mapper-multipath
		cp "$DIR"/multipath.conf /etc/multipath.conf
		tok systemctl enable multipathd
		tok systemctl start multipathd
		tok multipath -ll
		load_modules nvme_rdma nvme
	elif [ "$1" = "disable" ]; then
		tok multipath -F
		tok systemctl stop multipathd
		tok systemctl disable multipathd
		tok yum remove -y device-mapper-multipath
		unload_modules nvme_rdma nvme_fabrics nvme nvme_core
	fi
}

function update_iopolicy
{
	iopolicy=$1
	nvme_io_policy=$(find /sys | grep iopolicy)
	echo "$iopolicy" > "$nvme_io_policy"
}

function NVMEOF_RDMA_TARGET_CONNECT_E5700
{
	local IP=$1
	local HostNQN=$2
	tok "nvme discover -t rdma -a $IP"
	# shellcheck disable=SC2154
	tok nvme connect -t rdma -a "$IP" -n "$TargetNQN" -q "$HostNQN"
	ret=$?
	if (( ret == 0 )); then
		tlog "INFO: connect to $IP with $HostNQN pass"
	else
		tlog "INFO: connect to $IP with $HostNQN failed"
		tok nvme disconnect-all
		exit 1
	fi
}

function NVMEOF_RDMA_TARGET_SETUP() {

	EX_USAGE=64 # Bad arg format
	if [ $# -ne 1 ]; then
		echo 'Usage: NVMEOF_RDMA_Target_Setup IB|ROCE|iWARP|OPA'
		exit "${EX_USAGE}"
	fi
	if [[ $1 =~ IB|ROCE|iWARP|OPA ]]; then
		RDMA_protocol=$1
	else
		tlog "INFO: wrong parameter for \$1, should be IB|ROCE|iWARP|OPA"
		return 1
	fi

	#Change the IP address
	hn=$(hostname -s)
	if echo "$SERVERS:$CLIENTS" | grep -q "rdma-perf-06.*rdma-perf-07"; then
		[ "$RDMA_protocol" = "ROCE" ] && hn="$hn-server"
	elif echo "$SERVERS:$CLIENTS" | grep -q "rdma-perf-07.*rdma-perf-06"; then
		[ "$RDMA_protocol" = "ROCE" ] && hn="$hn-server"
	fi
	target_ip=$(grep "${RDMA_protocol}:${hn}" /root/NVME_RDMA_ENV | awk -F: '{print $4}')
	cp "$DIR"/rdma.json /etc/rdma.json
	sed -i "s#TRADDR_REPLACE#${target_ip}#g" /etc/rdma.json

	#change device path
	case $hn in
	rdma-perf-06*|rdma-perf-07*)
		device_path="/dev/nvme0n1"
		;;
	rdma*)
		modprobe null_blk nr_devices=2
		device_path="/dev/nullb0"
		;;
	*)
		tlog "non-supported test server $hn"
		trun "rm -f /etc/rdma.json"
		return 1
	esac
	sed -i "s#PATH_REPLACE#${device_path}#g" /etc/rdma.json
	tok nvmetcli restore /etc/rdma.json
}

#Get RDMA testing protocol target IP on client
function NVMEOF_RDMA_TARGET_IP() {

	EX_USAGE=64 # Bad arg format
	if [ $# -ne 1 ]; then
		echo 'Usage: NVMEOF_RDMA_Target_IP IB|ROCE|iWARP|OPA'
		exit "${EX_USAGE}"
	fi

	if [[ $1 =~ IB|ROCE|iWARP|OPA ]]; then
		RDMA_protocol=$1
	else
		tlog "INFO: wrong parameter for \$1, should be IB|ROCE|iWARP|OPA"
		exit 1
	fi
	#Get target NVMEOF RDMA IP ADDR
	hn=$(hostname -s)
	if echo "$SERVERS:$CLIENTS" | grep -q "rdma-perf-06.*rdma-perf-07"; then
		[ "$RDMA_protocol" = "ROCE" ] && hn="$(hostname -s)-client"
	elif echo "$SERVERS:$CLIENTS" | grep -q "rdma-perf-07.*rdma-perf-06"; then
		[ "$RDMA_protocol" = "ROCE" ] && hn="$(hostname -s)-client"
	fi
	target_ip=$(grep "${RDMA_protocol}:${hn}" /root/NVME_RDMA_ENV | awk -F: '{print $4}')
	# shellcheck disable=SC2034
	RETURN_STR="$target_ip"
}

#Disconnect target
function NVMEOF_RDMA_DISCONNECT_TARGET() {
	EX_USAGE=64 # Bad arg format
	if [ $# -ne 2 ]; then
		echo 'Usage: NVMEOF_RDMA_DISCONNECT_TARGET n|d testnqn|nvme1n1'
		exit "${EX_USAGE}"
	fi

	if [ "$1" = "n" ]; then
		tok nvme disconnect -n "$2"
	elif [ "$1" = "d" ]; then
		tok nvme disconnect -d /dev/"$2"
	else
		tlog "INFO: Wrong parameter for \$1, should be N|B"
		exit 1
	fi
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "INFO: nvme disconnect -$1 $2 failed"
	else
		tlog "INFO: nvme disconnect -$1 $2 pass"
	fi

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
	local runtime=180
	local numjobs=60
	if [ "${tmp_dev:0:5}" = "/dev/" ]; then
		test_dev=$tmp_dev
	else
		test_dev="/dev/${tmp_dev}"

	fi
	tlog "INFO: Executing FIO_Device_Level_Test() with device: $test_dev"

	#fio testing
	tok fio -filename="$test_dev" -iodepth=1 -thread -rw=write -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime="$runtime" -time_based -size=1G -group_reporting -name=mytest -numjobs="$numjobs"
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "FAIL: fio device level write testing for $test_dev failed"
		ret=1
	fi
	tok fio -filename="$test_dev" -iodepth=1 -thread -rw=randwrite -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime="$runtime" -time_based -size=1G -group_reporting -name=mytest -numjobs="$numjobs"
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "FAIL: fio device level randwrite testing for $test_dev failed"
		ret=1
	fi
	tok fio -filename="$test_dev" -iodepth=1 -thread -rw=read -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime="$runtime" -time_based -size=1G -group_reporting -name=mytest -numjobs="$numjobs"
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "FAIL: fio device level read testing for $test_dev failed"
		ret=1
	fi
	tok fio -filename="$test_dev" -iodepth=1 -thread -rw=randread -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -direct=1 -runtime="$runtime" -time_based -size=1G -group_reporting -name=mytest -numjobs="$numjobs"
	ret=$?
	if [ $ret -ne 0 ]; then
		tlog "FAIL: fio device level randread testing for $test_dev failed"
		ret=1
	fi

	return $ret
}

function FIO_Basic_Device_Level_Test() {
	EX_USAGE=64 # Bad arg format
	if [ $# -lt 1 ]; then
		echo "Usage: FIO_Basic_Device_Level_Test $test_dev"
		exit "${EX_USAGE}"
	fi
	# variable definitions
	local ret=0
	local tmp_dev=$1
	local runtime=180
	local numjobs=60
	if [ "${tmp_dev:0:5}" = "/dev/" ]; then
		test_dev=$tmp_dev
	else
		test_dev="/dev/${tmp_dev}"
	fi

	tlog "INFO: Executing FIO_Basic_Device_Level_Test() with device: $test_dev"
	trun "fio -filename=$test_dev -iodepth=1 -thread -rw=randwrite -ioengine=psync -bssplit=5k/10:9k/10:13k/10:17k/10:21k/10:25k/10:29k/10:33k/10:37k/10:41k/10 -bs_unaligned -runtime=$runtime -time_based -size=1G -group_reporting -name=mytest -numjobs=$numjobs" &
	sleep 3
}

function install_dt() {
	#Get dt
	trun which dt
	ret=$?
	if [ $ret -eq 0 ]; then
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
	ret=$?
	if [ $ret -eq 0 ]; then
		tlog "Fio already installed"
		return
	else
		tok yum install libaio-devel zlib-devel gcc -y
		tlog "Installing fio from git://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git"
		git_url=git://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git
		tok git clone $git_url
		tok "cd fio && ./configure && make && make install"
		tlog "Fio succesfully installed from source"
	fi
}

function install_iozone() {

	trun which iozone
	ret=$?
	if [ $ret -eq 0 ]; then
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
	pushd iozone3_490/src/current/ || return 1
	tok "make $target"
	tok "cp iozone /usr/bin/"
	tlog "Iozone succesfully installed"
}

function system_info_for_debug
{
	rpm -q kernel
	uname -r
	ibstat
	ibstatus
	ip addr show
}

function start_sm {
	if [[ $(hostname) == *"qe-14"*  || $(hostname) == *"qe-15"*  ||
	      $(hostname) == *"dev-15"* || $(hostname) == *"dev-16"* ]]; then
		# hfi1 device
		yum install -y  opa-fm
		/sbin/chkconfig opafm on
		/sbin/service opafm restart
	else
		# other device
		yum install -y opensm
		/sbin/service opensm restart
	fi
}
