#!/bin/bash
# This is for common install scripts
# shellcheck disable=SC2034,SC2044,SC2076

# default URL
EPEL_BASEURL=${EPEL_BASEURL:-"https://dl.fedoraproject.org/pub/epel/"}


# The same with task /distribution/command
exec_cmd()
{
	[ "$CMDS_TO_RUN" ] && eval "$CMDS_TO_RUN"
}

include_dir()
{
	# change path/kernel/networking/... to path/kernel/networking/common
	local path=$(pwd | sed 's#kernel/networking/.*#kernel/networking/common/#')
	echo $path | grep "/mnt/tests" || echo "/mnt/tests/kernel/networking/common/"
}

check_arch()
{
	if [ $(uname -m) == "aarch64" ] ; then
		sed -i 's/arm.*:Linux/aarch64*:Linux/' config.guess
	fi
	if [ $(uname -m) == "ppc64le" ] ; then
		sed -i 's/ppc64:Linux/ppc64*:Linux/' config.guess
	fi
}

if stat /run/ostree-booted > /dev/null 2>&1; then
	YUM="rpm-ostree -A --idempotent --allow-inactive install"
else
	YUM="yum -y install"
fi

#install ovs on rhel6/7
ovs_install()
{
	# check ovs-vsctl
	ovs-vsctl --help > /dev/null
	if [ $? != 0 ]; then
		release=$(GetDistroRelease)
		if [ $release -eq 6 ]; then
			local ovs="openvswitch"
			local ovs_el6_ver=${OVS_EL6_VER:-"2.3.1-2.git20150113.el6"}
			local major_ver=$(echo $ovs_el6_ver | cut -d'-' -f1)
			local minor_ver=$(echo $ovs_el6_ver | cut -d'-' -f2)
			local ovs_el6_url="http://download.devel.redhat.com/brewroot/packages/${ovs}/${major_ver}/${minor_ver}/$(uname -m)/${ovs}-${ovs_el6_ver}.$(uname -m).rpm"

			$YUM $ovs_el6_url || test_warn "ovs install fail"
		else
			cat - <<EOF > /etc/yum.repos.d/fast-datapath.repo
[fast-datapath]
name=fast-datapath
baseurl=http://download.devel.redhat.com/brewroot/repos/fast-datapath-rhel-${release}-build/latest/\$basearch/
enabled=1
gpgcheck=0
EOF
			if [ $release -eq 7 ]; then
				cat - <<EOF > /etc/yum.repos.d/extras-rhel.repo
[extras-rhel]
name=extras-rhel
baseurl=http://download.devel.redhat.com/brewroot/repos/extras-rhel-7.7-build/latest/\$basearch/
enabled=1
gpgcheck=0
EOF
			fi

			# It is openvswitch2.xx on rhel8 now
			# For example: openvswitch2.11.x86_64 : Open vSwitch
			$YUM openvswitch2.11 || $YUM openvswitch2.15 || $YUM openvswitch2.17 || test_warn "ovs install failed"
		fi
	fi
	# remove openstack repo incase it mess other repo
	rm -f /etc/yum.repos.d/fast-datapath.repo
	rm -f /etc/yum.repos.d/extras-rhel.repo
}

ssh_key_install()
{
	# For debug: make sure the user home dir's owner is itself
	grep -q "network-qe" ~/.ssh/authorized_keys &> /dev/null && return 0
	pushd ${NETWORK_COMMONLIB_DIR}

	# check .ssh dir
	umask 077
	test -d ~/.ssh || mkdir ~/.ssh

	# make sure the permission is correct
	chmod 600 ./keys/network_rsa
	if ! grep -q "network-qe" ~/.ssh/authorized_keys &> /dev/null; then
		cat ./keys/network_rsa.pub >> ~/.ssh/authorized_keys
		test -x /sbin/restorecon && \
			/sbin/restorecon ~/.ssh ~/.ssh/authorized_keys &> /dev/null
	fi
	chmod 600 ~/.ssh/authorized_keys

	if [ -f ~/.ssh/id_rsa ];then
		mv -f ~/.ssh/id_rsa ~/.ssh/id_rsa.bak
		mv -f ~/.ssh/id_rsa.pub ~/.ssh/id_rsa.pub.bak
	fi
	\cp -f ./keys/network_rsa ~/.ssh/id_rsa
	\cp -f ./keys/network_rsa.pub ~/.ssh/id_rsa.pub
	# FIXME: what should we do if we run with none-root user
	sed -i 's/^#[ ]*Strict/Strict/' /etc/ssh/ssh_config
	sed -i 's/^#[ ]*GSSAPI/GSSAPI/' /etc/ssh/ssh_config
	sed -i '/Strict/s/ask/no/' /etc/ssh/ssh_config
	grep -q "UserKnownHostsFile" /etc/ssh/ssh_config || \
		sed -i '/Strict/aUserKnownHostsFile no' /etc/ssh/ssh_config
	popd
}

ssh_key_uninstall()
{
	#sed -i '/network-qe/d' /root/.ssh/authorized_keys
	#rm -f /root/.ssh/id_rsa
	mv /root/.ssh/id_rsa /root/.ssh/network_rsa
	if [ -f /root/.ssh/id_rsa.bak ];then
		mv /root/.ssh/id_rsa.bak /root/.ssh/id_rsa
	fi
}

# Ncat tcp transport will fail when we put it background vai & on RHEL7
# Install traditional nc for RHEL7.
# this function will only cp nc to /usr/bin/
nc_install()
{
	$YUM nc
	if [ "$(GetDistroRelease)" -ne 7 ];then
		echo "Only install on RHEL7"
		return 0
	fi

	if [ -a /usr/bin/nc ];then
		mv /usr/bin/nc /usr/bin/nc_bak
	fi

	$YUM libbsd-devel
	wget $MY_URL/nc.tar.gz
	tar zxf nc.tar.gz

	pushd nc/
	make && make install
	if [ $? -ne 0 ];then
		test_fail "Install_NC_Fail"
	fi
	popd
}

lksctp_install()
{
	if [ -a /usr/include/netinet/sctp.h ]; then
		echo "lksctp have been installed"
		return 0
	fi

	# try yum first
	$YUM lksctp-tools-devel
	if [ -a /usr/include/netinet/sctp.h ]; then
		echo "lksctp installed success"
		return 0
	fi

	lksctp-tools_install
	return $?
}

lksctp-tools_install()
{
	[ -a /usr/local/bin/bindx_test ] && return 0

	pushd ${NETWORK_COMMONLIB_DIR}
	git clone https://github.com/sctp/lksctp-tools
	pushd lksctp-tools
	# An interim workaround, will remove this after upstream fix
	# https://github.com/sctp/lksctp-tools/issues/24
	[ -f src/include/linux/sctp.h ] && git checkout 3c8bd0d26b64611c690f33f5802c734b0642c1d8
	./bootstrap && ./configure && make && make install
	# Make sure the following test programs are installed
	pushd src/apps; install -c bindx_test nagle_snd nagle_rcv myftp sctp_xconnect \
		peel_server peel_client /usr/local/bin; popd
	popd
	popd

	if ! [ -a /usr/local/bin/bindx_test ];then
		echo "WARN : lksctp-tools install fail"
		test_warn "lksctp-tools_install_fail"
		return 1
	fi

	test_pass "lksctp-tools_install_pass"
	return 0
}

scapy_install()
{
	local scapy_git="https://github.com/secdev/scapy.git"
	local scapy_http="http://netqe-infra01.knqe.eng.rdu2.dc.redhat.com/share/tools/scapy.tar.gz"

	local rel=$(GetDistroRelease)
	[ $rel -ge 9 ] && dnf install -y scapy
	scapy -h && return 0

	[ -d scapy ] && rm -rf scapy
	# Try to get scapy from our own server first
	# It takes long time to do 'git clone' scapy from github sometimes,
	# which will make our job timeout.
	curl -k $scapy_http -o ./scapy.tar.gz
	if [ $? -eq 0 ]; then
		mkdir -p scapy && tar -xzf scapy.tar.gz -C scapy --strip-components=1
		pushd scapy
	else
		git clone ${scapy_git}
		pushd scapy
		if [ $rel -le 6 ]; then
			git checkout v2.2.0
			# fix ICMPv6MLQuery().hashret()
			# https://github.com/secdev/scapy/pull/335/commits/a1880b5ccfa0720d07aa77636b50af5e66f65ce9
			# This patch was applied to v2.3.3-13-ga1880b5, so the versions >= v2.4.0 have fixed the problem.
			# We can receive ICMPv6MLQuery packet via public NIC(which has ip like 10.*.*.*)which will break off scapy
			git cherry-pick a1880b5ccfa0720d07aa77636b50af5e66f65ce9
		else
			# Install version >= 2.4.0 on rhel7/8
			# This commit resolves the problem we met when running sctp/fuzz_init/
			# git checkout 900e8da87b4c5fe78d4253ded6f6132b2c268ddc
			git checkout v2.4.4
		fi
	fi

	# create /usr/local/lib/python3.6/site-packages/ directory if it doesn't exist
	# to avoid installation failures with RHEL-8.2
	if [[ ! -d /usr/local/lib/python3.6/site-packages/ ]]; then mkdir -p /usr/local/lib/python3.6/site-packages/; fi

	if /usr/libexec/platform-python -V &> /dev/null; then
		/usr/libexec/platform-python ./setup.py install
	elif python3 -V &> /dev/null ; then
		python3 ./setup.py install
	elif python2 -V &> /dev/null; then
		python2 ./setup.py install
	fi
	which scapy
	if [ $? -ne 0 ];then
		log "Scapy install failed"
		test_warn "Scapy_install_failed"
		exit 1
	fi
	popd
}

netperf_install()
{
	# rhel7 can't install from epel repo
	$YUM netperf
	if netperf -V;then
		return 0
	fi
	# force install lksctp for netperf sctp support
	lksctp_install

	local OUTPUTFILE=`mktemp /mnt/testarea/tmp.XXXXXX`

	#SRC_NETPERF=${SRC_NETPERF:-"http://netqe-infra01.knqe.lab.eng.bos.redhat.com/share/tools/netperf-20210121.tar.bz2"}
	SRC_NETPERF=${SRC_NETPERF:-"https://github.com/HewlettPackard/netperf/archive/refs/heads/master.tar.gz"}

	pushd ${NETWORK_COMMONLIB_DIR} 1>/dev/null
	wget -nv -N $SRC_NETPERF
	tar xvf $(basename $SRC_NETPERF)
	cd netperf-$(basename $SRC_NETPERF| awk -F. '{print $1}')
	check_arch
	./autogen.sh
	lsmod | grep sctp
	if [ $? -ne 0 ];then
		modprobe sctp
	fi
	if checksctp; then
		./configure --enable-sctp CFLAGS=-fcommon && make && make install | tee -a $OUTPUTFILE
	else
		./configure CFLAGS=-fcommon && make && make install | tee -a $OUTPUTFILE
	fi
	popd 1>/dev/null

	if ! netperf -V;then
		echo "WARN : Netperf install fail" | tee -a $OUTPUTFILE
		test_warn "Netperf_install_fail"
		return 1
	fi

	test_pass "Netperf_install_pass"
	return 0
}
iperf3_install()
{
	$YUM iperf3
	iperf3 -v && return 0
	local iperf3_version="iperf-3.1.3"
	pushd ${NETWORK_COMMONLIB_DIR}
	wget https://iperf.fr/download/source/${iperf3_version}-source.tar.gz
	tar -zxvf ${iperf3_version}-source.tar.gz
	pushd ${iperf3_version}
	./configure && make && make install
	popd
	popd
	iperf3 -v  && return 0 || return 1
}
iperf_install()
{
	which iperf && return 0
	CUR_PWD=$(pwd)
	$YUM gcc-c++ make gcc
	# grab sctp-enabled iperf and install it:
	IPERF_FILE="iperf-2.0.10.tar.gz"
	wget http://netqe-infra01.knqe.eng.rdu2.dc.redhat.com/share/tools/${IPERF_FILE}
	if [[ $? != 0 ]]; then
		echo "${TEST} fail grabbing iperf source"
		rstrnt-report-result "${TEST}_get_iperf" FAIL
		exit 1
	fi
	tar xf ${IPERF_FILE}
	if [[ $? != 0 ]]; then
		echo "${TEST} fail extracting ${IPERF_FILE}"
		rstrnt-report-result "${TEST}_extract_iperf" FAIL
		exit 1
	fi
	BUILD_DIR="${IPERF_FILE%.tar.gz}"
	cd ${BUILD_DIR}
	check_arch
	./configure && make && make install
	if [[ $? != 0 ]]; then
		echo "${TEST} fail installing iperf"
		rstrnt-report-result "${TEST}_install_iperf" FAIL
		exit 1
	fi
	IPERF_EXEC=$(which iperf)
	if [[ $? != 0 ]]; then
		echo "${TEST} fail finding sctp_iperf executable"
		rstrnt-report-result "${TEST}_find_iperf" FAIL
		exit 1
	fi
	cd ${CUR_PWD}
}
sockperf_install(){
	which sockperf && return 0
	$YUM gcc-c++ automake autoconf
	local sockperf_v=${1:-"3.6"}
	pushd ${NETWORK_COMMONLIB_DIR}
	wget https://github.com/Mellanox/sockperf/archive/${sockperf_v}.tar.gz
	tar -zxvf ${sockperf_v}.tar.gz
	pushd sockperf-${sockperf_v}
	./autogen.sh
	./configure --prefix=/usr/local/ --enable-test  --enable-tool --enable-debug
	make && make install
	popd
	popd
	sockperf -v  && return 0 || return 1
}
packetdrill_install()
{
	if [ -x ${NETWORK_COMMONLIB_DIR}/packetdrill/gtests/net/packetdrill/packetdrill ];then
		log "packetdrill has been installed"
		# create soft link in you local dir
		[ ! -e ./packetdrill ] && ln -s ${NETWORK_COMMONLIB_DIR}/packetdrill ./packetdrill
		return 0
	fi
	pushd ${NETWORK_COMMONLIB_DIR}
	$YUM bison flex glibc-static iproute-tc
	[ ! -e /usr/bin/python ] && ln -s /usr/libexec/platform-python /usr/bin/python
	git clone https://github.com/google/packetdrill.git
	pushd packetdrill
	git checkout -b rhel$(GetDistroRelease)
	if [ $(uname -m) != x86_64 ]; then
		patch -p1 < ../patch/packetdrill/special/increase_default_tolerance_usecs_for_non_x86_64.patch
	fi
	for p in `find ../patch/packetdrill/general -name "*.patch"`;do
		patch -p1 < $p || test_warn "patching fail: $p"
	done
	for p in `find ../patch/packetdrill/rhel$(GetDistroRelease) -name "*.patch"`;do
		patch -p1 < $p || test_warn "patching fail: $p"
	done
	pushd gtests/net/packetdrill
	./configure
	make
	popd
	popd
	popd
	[ ! -e ${NETWORK_COMMONLIB_DIR}/packetdrill/gtests/net/packetdrill/packetdrill ] && rm -rf ${NETWORK_COMMONLIB_DIR}/packetdrill && return 1
	# create soft link in you local dir
	ln -s ${NETWORK_COMMONLIB_DIR}/packetdrill ./packetdrill
	return 0
}

libsctp_static_install()
{
	local commit="57b003559078db2321e79b0c6dd85013fe7aa6e0"

	[ -a /usr/lib64/libsctp.a ] && return 0

	pushd ${NETWORK_COMMONLIB_DIR}
	rm -rf lksctp-tools
	git clone https://github.com/sctp/lksctp-tools
	pushd lksctp-tools
	./bootstrap && ./configure && make
	if [ $? -ne 0 ]; then
		# Please see comment in lksctp-tools_install()
		git checkout $commit
		make
	fi
	popd
	popd
	[ -a /usr/include/netinet/sctp.h ] || \
	ln -s ${NETWORK_COMMONLIB_DIR}/lksctp-tools/src/include/netinet/sctp.h /usr/include/netinet/sctp.h
	ln -sf ${NETWORK_COMMONLIB_DIR}/lksctp-tools/src/lib/.libs/libsctp.a /usr/lib64/libsctp.a
	[ -a /usr/lib64/libsctp.a ] && return 0 || return 1
}

packetdrill_uninstall()
{
	rm -rf /usr/local/bin/packetdrill
	pushd ${NETWORK_COMMONLIB_DIR}
	rm -rf packetdrill
	popd
}

packetdrill_sctp_install()
{
	[ -x /usr/local/bin/packetdrill_sctp ] && return 0
	# depends on sctp static lib
	libsctp_static_install

	pushd ${NETWORK_COMMONLIB_DIR}
	rpm -q glibc-static || $YUM glibc-static
	rm -rf packetdrill_sctp
	git clone https://github.com/nplab/packetdrill.git packetdrill_sctp
	local packetdrill_subdir="packetdrill_sctp/gtests/net/packetdrill"
	pushd $packetdrill_subdir
	./configure && make
	popd
	popd
	ln -sf ${NETWORK_COMMONLIB_DIR}/${packetdrill_subdir}/packetdrill /usr/local/bin/packetdrill_sctp
	[ -x /usr/local/bin/packetdrill_sctp ] && return 0 || return 1
}
# bz1191716: [RFE] mptcp support
packetdrill_mptcp_install()
{
	if [ -x ${NETWORK_COMMONLIB_DIR}/packetdrill_mptcp/gtests/net/packetdrill/packetdrill ]; then
		log "packetdrill_mptcp has been installed"
		# create soft link in you local dir
		[ ! -e ./packetdrill_mptcp ] && ln -s ${NETWORK_COMMONLIB_DIR}/packetdrill_mptcp ./packetdrill_mptcp
		return 0
	fi
	pushd ${NETWORK_COMMONLIB_DIR}
	$YUM bison flex glibc-static openssl-devel zlib-devel iproute iproute-tc
	[ ! -e /usr/bin/python ] && ln -s /usr/libexec/platform-python /usr/bin/python
	rm -rf packetdrill_mptcp
	git clone https://github.com/multipath-tcp/packetdrill packetdrill_mptcp
	pushd packetdrill_mptcp
	git checkout -b rhel$(GetDistroRelease)
	for p in `find ../patch/packetdrill_mptcp/general -name "*.patch"`;do
		patch -p1 < $p || test_warn "patching fail: $p"
	done
	if [ -e ../patch/packetdrill_mptcp/rhel$(GetDistroRelease) ]; then
		for p in `find ../patch/packetdrill_mptcp/rhel$(GetDistroRelease) -name "*.patch"`;do
			patch -p1 < $p || test_warn "patching fail: $p"
		done
	fi
	pushd gtests/net/packetdrill
	./configure && make
	popd
	popd
	popd
	[ ! -e ${NETWORK_COMMONLIB_DIR}/packetdrill_mptcp/gtests/net/packetdrill/packetdrill ] && rm -rf ${NETWORK_COMMONLIB_DIR}/packetdrill_mptcp && return 1
	# create soft link in you local dir
	ln -s ${NETWORK_COMMONLIB_DIR}/packetdrill_mptcp ./packetdrill_mptcp
	return 0
}

git_install()
{
	# only check whether git is installed at present
	# todo : add git install function
	if [ -a /usr/bin/git ];then
		log "Git have been installed"
		return 0
	else
		log "Git haven't been installed"
		test_warn "No_git"
		exit 1
	fi
}

# install ip netns support on RHEL6
iproute2_install()
{
	{ [ "$(GetDistroRelease)" -eq 7 ] || ip netns; } && return 0
	local OUTPUTFILE=$(new_outputfile)
	local iproute_ver=${IPROUTE_VER:-"2.6.32-130.el6eng.netns.2"}
	local major_ver=$(echo $iproute_ver | cut -d'-' -f1)
	local minor_ver=$(echo $iproute_ver | cut -d'-' -f2)
	local iproute_netns="http://download.devel.redhat.com/brewroot/packages/iproute/${major_ver}/${minor_ver}/$(uname -m)/iproute-${iproute_ver}.$(uname -m).rpm"

	yum -y update $iproute_netns || test_warn "iproute install fail"
	#check if install pass or not
	ip netns || return 1
}

tunctl_install()
{
	which tunctl && return
	pushd ${NETWORK_COMMONLIB_DIR}
	gcc patch/tunctl.c -o tunctl
	cp tunctl /usr/local/bin/
	popd
}

nping_install()
{
	if nping -V; then
		return 0
	fi

	local VERSION=0.6.01
	local MIN_VERSION=1
	local ARCH=$(uname -m)
	local URL=http://download.devel.redhat.com/qa/rhts/lookaside/nping-$VERSION-$MIN_VERSION.$ARCH.rpm
	wget -q $URL
	rpm -ivh nping-$VERSION-$MIN_VERSION.$ARCH.rpm
	if [[ $? != 0 ]]; then
		echo "${TEST} fail to install nping rpm packet"
		rstrnt-report-result "${TEST}_install_nping" FAIL
		exit 1
		fi
}

mtools_install()
{
	[ -f /usr/local/bin/msend ] && return 0
	pushd /usr/local/src/mtools
	sh build.sh
	popd
}

omping_install()
{
	which omping && return 0
	# try yum first
	$YUM omping && return 0
	#git clone git://git.fedorahosted.org/git/omping.git
	# fedorahosted is retired
	git clone https://github.com/troglobit/omping.git
	pushd omping
	make && make install
	popd
	which omping && return 0 || return 1
}

bfdd_install()
{
	which bfdd-beacon && return 0
	$YUM gcc-c++
	git glone https://github.com/dyninc/OpenBFDD.git
	pushd OpenBFDD
	aclocal
	autoconf
	autoheader
	./configure
	make
	make install
	popd
	which bfdd-beacon && return 0 || return 1
}

hping3_install()
{
	which hping && return 0
	$YUM libpcap-devel tcl-devel
	ln -s /usr/include/pcap/bpf.h /usr/include/net/bpf.h
	git clone https://github.com/antirez/hping.git
	pushd hping
	./configure && make && make install
	popd
	which hping && return 0 || return 1
}

rhscl_repo_install()
{
	cat - <<EOF > /etc/yum.repos.d/rhscl.repo
[rhscl]
name=rhscl
baseurl=http://download.devel.redhat.com/rel-eng/latest-RHSCL-3-RHEL-$(GetDistroRelease)/compose/Server/$(uname -m)/os/
enabled=1
gpgcheck=0
EOF

}
httpd24_install()
{
	rpm -q httpd24-httpd && return 0
	rhscl_repo_install
	$YUM httpd24 httpd24-mod_ssl && return 0
}

epel_release_install()
{
	local release=$(GetDistroRelease)
	local epel_fullurl=${EPEL_BASEURL}/epel-release-latest-${release}.noarch.rpm

	[ "`rpm -qa | grep epel-release`" ] && return 0
	# We rarely run test on RHEL5, rhel8 epel is available now.
	if [[ "$release" -le 5 || "$release" -ge 10 ]]; then
		return 0
	fi
	rpm -ivh --force --nodeps $epel_fullurl && return 0 || return 1
}

# Supports BREW_TASK_ID, KERNEL_LINK, KERNEL_VERSION
kernel_install()
{
	local karch baseurl rpmpkg rpmpkgs knvr krel kernel pkg pkgs brew_url task_id noarch_id firmurl
	karch=$(uname -m)

	# FIXME: if we need to deal with build id and none parent task, see
	# task distribution/install/brew-build
	if [ "$BREW_TASK_ID" ]; then
		brew_url="https://brewweb.engineering.redhat.com"
		wget --no-check-certificate ${brew_url}/brew/taskinfo?taskID=${BREW_TASK_ID} -O ${BREW_TASK_ID}.html
		if grep -q '<span class="treeLabel">' ${BREW_TASK_ID}.html; then
			task_id=$(grep -A 2 '<span class="treeLabel">' ${BREW_TASK_ID}.html | grep $karch | egrep -o 'taskID=[0-9]+' | cut -d '=' -f 2)
			noarch_id=$(grep -A 2 '<span class="treeLabel">' ${BREW_TASK_ID}.html | grep "kernel.*noarch" | egrep -o 'taskID=[0-9]+' | cut -d '=' -f 2)
			wget --no-check-certificate ${brew_url}/brew/taskinfo?taskID=${task_id} -O ${task_id}.html
			export KERNEL_LINK=$(grep "${karch}\.rpm</a>" ${task_id}.html | egrep -o 'http[s]?://[^"]*' | grep "kernel-[1-9]\.")
			# FIXEME: not sure if it should be 0123/ or 123/
			wget --no-check-certificate ${brew_url}/brew/taskinfo?taskID=${noarch_id} -O ${noarch_id}.html
			firmware_pkg=$(grep "kernel-firmware.*noarch\.rpm</a>" ${noarch_id}.html | egrep -o 'http[s]?://[^"]*')
		else
			test_fail "Not valid parent brew task id ${BREW_TASK_ID}"
			return 1
		fi

	fi
	if [ "$KERNEL_LINK" ]; then
		rpmpkg=$(echo $KERNEL_LINK | awk -F'/' '{print $NF}')
		baseurl=$(echo $KERNEL_LINK | sed "s/\/${rpmpkg}//")
		knvr=$(echo $rpmpkg | sed "s/\.${karch}\.rpm//" | awk -F- '{print $(NF-1)}')
		krel=$(echo $rpmpkg | sed "s/\.${karch}\.rpm//" | awk -F- '{print $NF}')
		pkg=$(echo $rpmpkg | sed "s/-${knvr}-${krel}.${karch}.rpm//")
		echo $pkg | grep -q debug && KERNEL_DEBUG=1
	elif [ "$KERNEL_VERSION" ]; then
		if [ "$OWNER" ]; then
			baseurl="http://brew-task-repos.usersys.redhat.com/repos/scratch/$OWNER"
		else
			baseurl="http://download.devel.redhat.com/brewroot/packages"
		fi

		echo $KERNEL_VERSION | grep -q el7a && \
			baseurl="$baseurl/kernel-alt" || \
			baseurl="$baseurl/kernel"

		knvr=$(echo $KERNEL_VERSION | awk -F- '{print $(NF-1)}')
		krel=$(echo $KERNEL_VERSION | awk -F- '{print $NF}')
		baseurl="${baseurl}/${knvr}/${krel}/${karch}"
		firmurl="${baseurl}/${knvr}/${krel}/noarch"

		echo $KERNEL_VERSION | grep -q debug && KERNEL_DEBUG=1
		[ "$KERNEL_DEBUG" ] && pkg="kernel-debug" || pkg="kernel"
		firmware_pkg=${firmurl}/${pkg}-${knvr}-${krel}.noarch.rpm
	else
		test_warn "No kernel info, we need KERNEL_LINK or KERNEL_VERSION"
		return
	fi

	kernel="${knvr}-${krel}.${karch}"
	if [ "$KERNEL_DEBUG" ]; then
		if [[ "$krel" =~ ".el6" ]] && [[ "$krel" =~ ".el7" ]] ; then
			kernel="${kernel}.debug"
		else
			kernel="${kernel}+debug"
		fi
	fi
	if [ -z $REBOOTCOUNT ] || [ $REBOOTCOUNT -eq 0 ]; then
		run "$YUM linux-firmware kexec-tools"
		run "$YUM grubby"
		if [[ "$krel" =~ ".el6" ]]; then
			pkgs="$pkg kernel-firmware"
		elif [[ "$krel" =~ ".el7" ]]; then
			pkgs="$pkg"
		else
			pkgs="$pkg ${pkg}-core ${pkg}-modules ${pkg}-modules-extra ${pkg}-modules-internal"
		fi

		if [ "$INSTALL_SELFTESTS" ]; then
			run "$YUM iproute-tc"
			pkgs="$pkgs kernel-selftests-internal bpftool"
		fi

		if [ "$INSTALL_DEBUGINFO" ]; then
			pkgs="$pkgs ${pkg}-debuginfo kernel-debuginfo-common-${karch}"
		fi

		for pkg in $pkgs; do
			if echo $pkg | grep -q kernel-firmware; then
				run "wget -nv --no-check-certificate $firmware_pkg"
				rpmpkgs="${rpmpkgs} ${pkg}-${knvr}-${krel}.noarch.rpm"
			else
				run "wget -nv --no-check-certificate ${baseurl}/${pkg}-${knvr}-${krel}.${karch}.rpm"
				rpmpkgs="${rpmpkgs} ${pkg}-${knvr}-${krel}.${karch}.rpm"
			fi
		done

		run "$YUM $rpmpkgs " || \
			{ test_fail "install kernel failed" && return; }

		# update kernel to default
		which grubby || { test_fail "no grubby" && return; }

		boot_img="/boot/vmlinuz-$kernel"
		run "grubby --set-default ${boot_img}"
		run "grubby --default-kernel"

		sleep 10
		[ "$JOBID" ] && rhts-reboot || reboot
	else
		run "uname -a"
		uname -r | grep $kernel && \
			test_pass "install kernel pass" ||
			test_fail "install kernel fail"
	fi
}

devtoolset_install()
{
	ver=${1:-"8"}
	rpm -q devtoolset-${ver}-toolchain && return 0
	rhscl_repo_install
	$YUM devtoolset-${ver}-toolchain
}

kernel_modules_extra_install()
{
	local kername=$(rpm -q --queryformat '%{name}\n' -qf /boot/config-$(uname -r))
	local kernver=$(rpm -q --queryformat '%{version}\n' -qf /boot/config-$(uname -r))
	local kernrel=$(rpm -q --queryformat '%{release}\n' -qf /boot/config-$(uname -r))
	local kernarch=$(rpm -q --queryformat '%{arch}\n' -qf /boot/config-$(uname -r))
	local yumcmd="yum"

	# drop -core/-debug from name if present
	ker_prefix=$(echo $kername | sed 's/-core//')
	kername=$(echo $ker_prefix | sed 's/-debug//')
	rpm -qa | grep ${ker_prefix}-modules-extra-${kernver}-${kernrel}.${kernarch} && return 0
	local KERNPKGDIRECTORY="$kername"
	local httpbase=http://download.devel.redhat.com/brewroot/packages/$KERNPKGDIRECTORY/$kernver/$kernrel
	local kernmodulesextra=${ker_prefix}-modules-extra-${kernver}-${kernrel}.${kernarch}
	if stat /run/ostree-booted > /dev/null 2>&1; then
		rpm-ostree -A --idempotent --allow-inactive install \
			$httpbase/$kernarch/$kernmodulesextra.rpm
	else
		$yumcmd -y localinstall --nogpgcheck \
			$httpbase/$kernarch/$kernmodulesextra.rpm
	fi
}

kselftests_install()
{
	. ../../../automotive/include/rhivos.sh
	local kname1="kernel"
	local kname2="${kname1}"
	local kernel_ver="$(uname -r)"
	if  kernel_rt; then
		kname2="${kname1}-rt"
	fi
	if kernel_automotive; then
		kname2="${kname1}-automotive"
	fi
	if  kernel_debug; then
		kname2="${kname1}-debug"
		kernel_ver="$(uname -r| sed 's/.debug//')"
	fi
	if stat /run/ostree-booted > /dev/null 2>&1; then
		rpm-ostree install -A --idempotent --allow-inactive iproute-tc libbpf
		rpm-ostree install -A --idempotent --allow-inactive bpftool
		rpm-ostree install -A --idempotent --allow-inactive ${kname2}-modules-extra
		rpm-ostree install -A --idempotent --allow-inactive ${kname2}-modules-internal
		rpm-ostree install -A --idempotent --allow-inactive ${kname2}-selftests-internal
	else
		dnf install -y iproute-tc libbpf #dependencies
		dnf install -y bpftool-${kernel_ver} ${kname2}-modules-extra-${kernel_ver} ${kname2}-modules-internal-${kernel_ver} ${kname2}-selftests-internal-${kernel_ver} && return 0
		local link="http://download.devel.redhat.com/brewroot/packages/${kname1}"
		local karch=$(uname -m)
		local kver=$(echo ${kernel_ver}| cut -f1 -d'-')
		local krel=$(echo ${kernel_ver} | cut -f2 -d'-' | sed "s/\.$karch//")
		dnf install  -y ${link}/${kver}/${krel}/${karch}/bpftool-${kver}-${krel}.${karch}.rpm
		dnf install  -y ${link}/${kver}/${krel}/${karch}/${kname2}-modules-extra-${kver}-${krel}.${karch}.rpm
		dnf install  -y ${link}/${kver}/${krel}/${karch}/${kname2}-modules-internal-${kver}-${krel}.${karch}.rpm
		dnf install  -y ${link}/${kver}/${krel}/${karch}/${kname2}-selftests-internal-${kver}-${krel}.${karch}.rpm
	fi
	[ -e /usr/libexec/kselftests ] && return 0 || return 1
}

brew_install()
{
	[[ -z "$brew_list" ]] && return 0

	local rhel_major=$(sed -n 's/.* \([0-9]\+\)\..*/\1/p' /etc/redhat-release)
	mkdir brew_install
	pushd brew_install
	wget http://download.devel.redhat.com/rel-eng/RCMTOOLS/rcm-tools-rhel-${rhel_major}-baseos.repo -P /etc/yum.repos.d/
	$YUM brewkoji --nogpgcheck

	local p=""
	for p in $brew_list
	do
		brew download-build $p --arch $(uname -m) --arch noarch
	done
	$YUM *
	popd
}

brew_install
