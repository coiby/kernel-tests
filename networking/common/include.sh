#!/bin/bash

# dynamically get the lib dir
NETWORK_COMMONLIB_DIR=$(dirname $(readlink -f $BASH_SOURCE))
networkLib=$NETWORK_COMMONLIB_DIR

# include beaker default environmnet
. /usr/bin/rhts_environment.sh
. /usr/share/beakerlib/beakerlib.sh || . /usr/lib/beakerlib/beakerlib.sh

# variables to control some default action
NM_CTL=${NM_CTL:-"no"}
FIREWALL=${FIREWALL:-"no"}
AVC_CHECK=${AVC_CHECK:-"yes"}
SET_DMESG_CHECK_KEY=${SET_DMESG_CHECK_KEY:-"no"}

if [ ! "$JOBID" ] && [ ! "$RSTRNT_JOBID" ]; then
	RED='\E[1;31m'
	GRN='\E[1;32m'
	YEL='\E[1;33m'
	RES='\E[0m'
fi

if stat /run/ostree-booted > /dev/null 2>&1; then
	YUM="rpm-ostree -A --idempotent --allow-inactive install"
else
	YUM="yum -y install"
fi

# Create tmp directory
mkdir -p /mnt/testarea

new_outputfile()
{
	mktemp /mnt/testarea/tmp.XXXXXX
}

setup_env()
{
	# install dependence
	# save testing environment
	# export our new variable
	export PASS=0
	export FAIL=0
	export WARN=0
	export SKIP=0
	export OUTPUTFILE=$(new_outputfile)
	reset_network_env
}

clean_env()
{
	# clean environment
	# restore environment
	unset PASS
	unset FAIL
	unset WARN
	unset SKIP
	reset_network_env
}

log()
{
	echo -e "\n[$(date '+%T')][$(whoami)@$(uname -r | cut -f 2 -d-)]# " | tee -a $OUTPUTFILE
	echo -e "\n[  LOG: $1  ]" | tee -a $OUTPUTFILE
}

submit_log()
{
	[ ! $JOBID ] && [ ! $RSTRNT_JOBID ] && return 0
	for file in "$@"; do
		rhts-submit-log -l $file
	done
}

test_pass()
{
	let PASS++
	SCORE=${2:-$PASS}
	echo -e "\n:: [  PASS  ] :: Test '$1'" | tee -a $OUTPUTFILE
	# we don't care how many test passed
	if [ $JOBID ] || [ $RSTRNT_JOBID ]; then
		report_result "${TEST}/$1" "PASS"
	else
		echo -e "\n::::::::::::::::"
		echo -e ":: [  ${GRN}PASS${RES}  ] :: Test '"${TEST}/$1"'"
		echo -e "::::::::::::::::\n"
	fi
}

test_fail()
{
	let FAIL++
	SCORE=${2:-$FAIL}
	echo -e ":: [  FAIL  ] :: Test '$1'" | tee -a $OUTPUTFILE
	# we only care how many test failed
	if [ $JOBID ] || [ $RSTRNT_JOBID ]; then
		report_result "${TEST}/$1" "FAIL" "$SCORE"
	else
		echo -e "\n:::::::::::::::::"
		echo -e ":: [  ${RED}FAIL${RES}  ] :: Test '"${TEST}/$1"' FAIL $SCORE"
		echo -e ":::::::::::::::::\n"
	fi
}

test_warn()
{
	let WARN++
	SCORE=${2:-$WARN}
	echo -e "\n:: [  WARN  ] :: Test '$1'" | tee -a $OUTPUTFILE
	if [ $JOBID ] || [ $RSTRNT_JOBID ]; then
		report_result "${TEST}/$1" "WARN" "${SCORE}"
	else
		echo -e "\n:::::::::::::::::"
		echo -e ":: [  ${YEL}WARN${RES}  ] :: Test '"${TEST}/$1"'"
		echo -e ":::::::::::::::::\n"
	fi
}

test_skip()
{
	let SKIP++
	SCORE=${2:-$SKIP}
	echo -e "\n:: [  SKIP  ] :: Test '$1'" | tee -a $OUTPUTFILE
	if [ $JOBID ] || [ $RSTRNT_JOBID ]; then
		report_result "${TEST}/$1" "SKIP" "${SCORE}"
	else
		echo -e "\n:::::::::::::::::"
		echo -e ":: [  ${YEL}SKIP${RES}  ] :: Test '"${TEST}/$1"'"
		echo -e ":::::::::::::::::\n"
	fi
}

test_pass_exit()
{
	test_pass "$1"
	exit 0
}

test_fail_exit()
{
	test_fail "$1"
	exit 1
}

test_warn_exit()
{
	test_fail "$1"
	exit 1
}

test_skip_exit()
{
	test_skip "$1"
	exit 1
}

i_am_server() {
	echo $SERVERS | grep -q $HOSTNAME
}

i_am_client() {
	echo $CLIENTS | grep -q $HOSTNAME
}

i_am_standalone() {
	echo $STANDALONE | grep -q $HOSTNAME
}

# Usage: run command [return_value]
run()
{
	cmd=$1
	# FIXME: only support zero or none zero, doesn't support 2-10, or 2,3,4
	exp=${2:-0}
	echo -e "\n[$(date '+%T')][$(whoami)@$(uname -r | cut -f 2 -d-)]# '$cmd'" | tee -a $OUTPUTFILE
	# FIXME: how should we handle if there are lots of output for the cmd,
	# and we only care the return value
	#eval "$cmd" &> >(tee -a $OUTPUTFILE)
	eval "$cmd" > >(tee -a $OUTPUTFILE)
	local ret=$?
	if [ "$exp" -eq "$ret" ];then
		echo -e ":: [  ${GRN}PASS${RES}  ] :: Command '$cmd' (Expected $exp, got $ret, score $PASS)" | tee -a $OUTPUTFILE
		return 0
	else
		echo -e ":: [  ${RED}FAIL${RES}  ] :: Command '$cmd' (Expected $exp, got $ret, score $FAIL)" | tee -a $OUTPUTFILE
		return 1
	fi
}

# Usage: watch command timeout [signal]
watch()
{
	command=$1
	timeout=$2
	single=${3:-9}
	now=`date '+%s'`
	after=`date -d "$timeout seconds" '+%s'`

	eval "$command" &
	pid=$!
	while true; do
		now=`date '+%s'`

		if ps -p $pid; then
			if [ "$after" -gt "$now" ]; then
				sleep 10
			else
				log "command (# $command) still alive, kill it"
				kill -$single $pid
				break
			fi
		else
			log "command (# $command) exit itself"
			break
		fi
		done
}

get_round()
{
	# pushd to include dir to make sure our $round is specific
	PWD=$(pwd)
	cd ${NETWORK_COMMONLIB_DIR}
	if [ ! -e my.round ];then
		echo 1 > my.round
		round=1
	else
		round=`cat my.round`
		let round++
		echo $round > my.round
	fi
	cd $PWD
	echo $round
}
# sync is a linux file system cmd. use net_sync instead
net_sync()
{
	local FLAG=$1
	# only enalbe get_round when (no JOBID and no DONT_GET_ROUND)
	if [ ! "$JOBID" ] && [ ! $RSTRNT_JOBID ] && [ ! "$DONT_GET_ROUND" ];then
		FLAG="$(get_round)_${FLAG}"
	fi
	log "Start sync ${FLAG}"
	if $(echo $SERVERS | grep -q -i $HOSTNAME);then
		rhts-sync-set -s ${FLAG}
		for client in $CLIENTS; do
			rhts-sync-block -s ${FLAG} $client
		done
	elif $(echo $CLIENTS | grep -q -i $HOSTNAME);then
		for server in $SERVERS; do
			rhts-sync-block -s ${FLAG} $server
		done
		rhts-sync-set -s ${FLAG}
	fi
	log "Finish sync ${FLAG}"
}
net-sync()
{
	net_sync $1
}

# We only care the main distro
GetDistroRelease()
{
	source /etc/os-release
	echo $VERSION_ID | awk -F. '{print $1}'
}

get_python()
{
	PYTHON=${PYTHON:-python}
	if /usr/libexec/platform-python -V &> /dev/null; then
		PYTHON="/usr/libexec/platform-python"
	elif python3 -V &> /dev/null; then
		PYTHON="python3"
	elif python2 -V &> /dev/null; then
		PYTHON="python2"
	fi
	echo ${PYTHON}
}

#Usage: rmmodule MODULENAME
#unload module and it's holders.
#Note: If this function stuck,you should handle it on your own.
#     Check if successful unload after call rmmodule.
rmmodule()
{
	local module=$1
	modprobe -q -r $module && return 0
	test -e /sys/module/$module || { echo "FATAL: Module $module not found.";return 1; }
	local holders=`ls /sys/module/$module/holders/`
	for item in $holders;do
		rmmodule $item
	done
	modprobe -q -r $module
}

# beaker plugin dmesg_check will recognize failurestrings as failure
# and will omit falsestrings
set_dmesg_check_key()
{
	if [ "$SET_DMESG_CHECK_KEY" != "yes" ];then
		return
	fi
	mkdir -p /usr/share/rhts/
	cat >/usr/share/rhts/failurestrings <<EOF
Oops
BUG
Kernel panic
Call Trace
Call trace
cut here
Unit Hang
watchdog: BUG: soft lockup - CPU
hw csum failure
failed to load firmware image
firmware error detected
NMI appears to be stuck
Badness at
probe of .* failed with error
unregister_netdevice: waiting for .* to become free
hwrm .* error
saving vmcore
saving vmcore-dmesg.txt complete
Starting Kdump Vmcore Save Service
EOF

	cat >/usr/share/rhts/falsestrings <<EOF
BIOS BUG
DEBUG
mapping multiple BARs.*IBM System X3250 M4
probe of i8042 failed
EOF
}

# https://bugzilla.redhat.com/show_bug.cgi?id=2119694
# without this, ssh to some cisco switches will fail since crypto-policies-20220815-1.git0fbe86f.el9.noarch
config_ssh()
{
	local crypto_version=$(rpm -q crypto-policies| awk -F"-" '{print $3}')
	if ((crypto_version>=20220815));then
		cat >> /root/.ssh/config <<- EOF
		Host 10.73.88.7 10.73.88.10 10.73.130.8 10.73.130.9 10.16.223.1 10.73.130.13 10.73.130.11
		RSAMinSize 1024
		EOF
	fi
}

install_required_packages()
{
	# make sure all required packages are installed
	if [ -x /usr/sbin/kernel-is-rt ]; then
		if stat /run/ostree-booted > /dev/null 2>&1; then
			packages=`awk -F: '/softDependencies=/{print $1}' metadata | awk -F'=' '{print $2}' | sed 's/;/ /g'`
			rpm-ostree install -A --idempotent --allow-inactive $packages
			rpm-ostree -A --idempotent --allow-inactive install openssh-clients
			ssh_client_version=`rpm -q openssh-clients --info | grep -o -E "Version.*: [0-9]+" | awk '{print $3}'`
		else
			yum install openssh-clients -y
			ssh_client_version=`yum info openssh-clients | grep -o -E "Version.*: [0-9]+" | awk '{print $3}'`
		fi
	else
		if stat /run/ostree-booted > /dev/null 2>&1; then
			packages=`awk -F: '/softDependencies=/{print $1}' metadata | awk -F'=' '{print $2}' | sed 's/;/ /g'`
			rpm-ostree install -A --idempotent --allow-inactive $packages
			kernel_modules_extra_install
			rpm-ostree -A --idempotent --allow-inactive install kernel-modules-extra

			# ssh to switch would fail with error "no matching key exchange method found. Their offer: diffie-hellman-group1-sha1" on rhel8
			# add extra configuration for ssh
			rpm-ostree -A --idempotent --allow-inactive install openssh-clients
			ssh_client_version=`rpm -q openssh-clients --info | grep -o -E "Version.*: [0-9]+" | awk '{print $3}'`
		else
			# install kernel-module-extra version matching the current running kernel version
			# Don't try to install kernel-modules-extra pacakges if kernel is not from rpm packages
			# for exmaple, cki kernel builds for upstream kernel tree are tarball not rpm, in this case
			# kernel-modules-extra is not available
			if rpm -qf /boot/config-$(uname -r) > /dev/null 2>&1; then
				yum info kernel-modules-extra && kernel_modules_extra_install
				yum install kernel-modules-extra -y --skip-broken
			fi

			# ssh to switch would fail with error "no matching key exchange method found. Their offer: diffie-hellman-group1-sha1" on rhel8
			# add extra configuration for ssh
			yum install openssh-clients -y
			ssh_client_version=`yum info openssh-clients | grep -o -E "Version.*: [0-9]+" | awk '{print $3}'`
		fi
	fi
}

main()
{
	# source our functions
	pushd $NETWORK_COMMONLIB_DIR > /dev/null
	for lib in *.sh; do
		# skip self and runtest.sh
		[[ "$lib" = "include.sh" || "$lib" = "runtest.sh" ]] && continue
		source ./$(basename $lib)
	done

	# handle the initial task just once
	if [ -f /dev/shm/network_common_initalized ]
	then
		# avc_check toggle every time common is called as avc setting may be
		# reset by beaker or others
		[ "$AVC_CHECK" = yes ] && enable_avc_check || disable_avc_check
	else
		{
		if [ "$(uname -m)" = "ppc64le" ]; then
			sleep 2;
		fi

		install_required_packages

		ssh_client_version=${ssh_client_version:-5}
		if [ $ssh_client_version -ge 7 ]
		then
			if ! grep diffie-hellman-group1-sha1 ~/.ssh/config
			then
				[ ! -d ~/.ssh ] && mkdir -p ~/.ssh
				echo "Host *" >> ~/.ssh/config
				echo "KexAlgorithms +diffie-hellman-group1-sha1" >> ~/.ssh/config
			fi
		fi

		# install customer tools
		mkdir -p /usr/local/src /usr/local/bin
		\cp -af src/* /usr/local/src/.
		\cp -af tools/* /usr/local/bin/.
		chmod a+x /usr/local/bin/*

		# work around bz883695
		lsmod | grep mlx4_en || modprobe mlx4_en
		# work around bz1642795
		lsmod | grep sctp || modprobe sctp

		if [[ "$PERSISTENT_CONFIG" != "yes" ]]; then
			if [ "$(GetDistroRelease)" -le 8 ];then
				[ -d $networkLib/network-scripts.bak ] || \
					rsync -a --delete /etc/sysconfig/network-scripts/ $networkLib/network-scripts.bak/
			else
				[ -d $networkLib/system-connections ] || \
					rsync -a --delete /etc/NetworkManager/system-connections/ $networkLib/system-connections/
			fi
		fi

		# NetworkManger toggle
		[ "$NM_CTL" = yes ] || stop_NetworkManager

		# firewall toggle
		[ "$FIREWALL" = yes ] && enable_firewall || disable_firewall

		# avc_check toggle
		[ "$AVC_CHECK" = yes ] && enable_avc_check || disable_avc_check

		set_dmesg_check_key

		rhel_vx=$(GetDistroRelease)
		if [ $rhel_vx -ge 9 ];then
			# avoid ssh "no matching cipher found" issue
			if ! grep -v ^# /etc/ssh/ssh_config | grep -q Ciphers;then
				sed -i '$a Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-cbc,3des-cbc,aes192-cbc,aes256-cbc' /etc/ssh/ssh_config
			fi
		fi

		# install dhcp-client
		$YUM dhcp-client

		config_ssh

		touch /dev/shm/network_common_initalized
	}
	fi

	popd > /dev/null
}

# use our own rhts-sync for manually testing
if [ ! "$JOBID" ] && [ ! $RSTRNT_JOBID ];then
ssh_key_install
rhts-sync-set()
{
	local message=$2
	local timeout=3600
	local peer_host=""
	local resend=1

	if   i_am_client; then peer_host="$SERVERS"
	elif i_am_server; then peer_host="$CLIENTS"
	else peer_host=$HOSTNAME
	fi
	until [ $timeout -le 0 ] || [ $resend -eq 0 ]; do
		let resend=0
		for host in $peer_host; do
			ssh $host "echo $HOSTNAME $message >> /tmp/sync_message" 2>/dev/null || let resend++;
		done
		sleep 5
		let timeout=timeout-5
	done
	if [ $timeout -le 0 ]; then test_warn "rhts-sync-set $HOSTNAME $message failed"; fi
	echo "rhts-sync-set -s $message DONE"
}

rhts-sync-block()
{
	local message=$2
	local i
	shift; shift
	hosts=($@)
	for i in "${hosts[@]}"; do
		local key="$i $message"
		while true; do
			grep "$key" /tmp/sync_message 2>/dev/null && {
				sed -i "/$key/d" /tmp/sync_message
				break
			}
			echo "$(date '+%b %d %T') Waiting $key"
			sleep 5
		done
	done
#	echo "rhts-sync-block -s $message $@ DONE"
#	https://www.shellcheck.net/wiki/SC2145
	echo "rhts-sync-block -s $message $* DONE"
}
fi

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
	main
fi
