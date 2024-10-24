#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#    Copyright (c) 2014 Red Hat, Inc. All rights reserved.
#
#    This copyrighted material is made available to anyone wishing
#    to use, modify, copy, or redistribute it subject to the terms
#    and conditions of the GNU General Public License version 2.
#
#    This program is distributed in the hope that it will be
#    useful, but WITHOUT ANY WARRANTY; without even the implied
#    warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#    PURPOSE. See the GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public
#    License along with this program; if not, write to the Free
#    Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#    Boston, MA 02110-1301, USA.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || . /usr/lib/beakerlib/beakerlib.sh || exit 1
. ../../kernel-include/runtest.sh || exit 1

#--------------------------
#Put Required packages here
#--------------------------
dependences=( \
	nmap-ncat lksctp-tools \
	tcpdump conntrack-tools \
	nftables ipset ipvsadm \
)

if uname -r | grep -q "\.el10"; then
	dependences+=( "$(K_GetRunningKernelRpmSubPackageNVR modules-extra)" )
fi

left=()
WORK_PATH=$(pwd)

#---------------------------------------------
# find_proper_version():
# Find a suitable version for RHEL6/7/8.
# Others release use upstream lastest version.
# http://www.netfilter.org/projects/index.html
#
# Usage: <Pkgname> <Release> <@version>
# @version: variable to save the result
#---------------------------------------------
find_proper_version()
{
	local Pkgname=$1
	local Release=$2
	local _output=$3
	local version
# FIXME: Update VerMap future
cat > VerMap <<-EOF
Pkgname\Release             RHEL6       RHEL7       RHEL8
iptables                    1.4.7       1.4.21      1.8.4
nftables                    N/A         0.8         0.9.3
libnftnl                    N/A         1.0.8       1.1.5
libnfnetlink                1.0.0       1.0.1       1.0.1
libnetfilter_acct           N/A         N/A         N/A
libnetfilter_log            N/A         N/A         N/A
libnetfilter_queue          1.0.1       1.0.2       1.0.4
libnetfilter_conntrack      0.0.100     1.0.6       1.0.6
libnetfilter_cttimeout      N/A         1.0.0       1.0.0
libnetfilter_cthelper       N/A         1.0.0       1.0.0
conntrack-tools             N/A         1.4.4       1.4.4
ipset                       6.11        7.1         7.1
nfacct                      N/A         N/A         N/A
ulogd                       N/A         N/A         N/A
libmnl                      1.0.2       1.0.3       1.0.4
EOF

cat > search.awk <<'EOF'
BEGIN {
	name = ARGV[1]
	release = ARGV[2]
	ARGV[1]=""
	ARGV[2]=""
	result = NotFound;
	col = 255;
	FS=" "
}
{
	if (NR == 1) {
		for (i = 1; i <= NF; i++) {
			if ($i == release) {
				col = i;
				break;
			}
		}
	}
	if (col == 255) {
		exit 1;
	}
	if ($1 == name) {
		result = $col;
		exit 0;
	}
}

END {
	if (col == 255) {
		printf ("awk: release = [%s] not found !\n", release);
		exit 1;
	}
	if (result == NotFound) {
		printf ("awk: package name = [%s] not found !\n", name);
		exit 2;
	}
	if (result == "N/A") {
		printf ("awk: result Not appicable !\n", name);
		exit 3;

	}
	printf("%s\n", result);
}
EOF
	version=$(cat VerMap | awk -f search.awk $Pkgname $Release)
	if [[ $? != 0 ]];then
		# Find upstream lastest version
		wget https://www.netfilter.org/projects/$Pkgname/files -O $Pkgname.html 1>/dev/null 2>/dev/null || \
		{ echo "connect to www.netfilter.org fail"; return 2; }
		version=`grep -Po "$Pkgname.*?tar" $Pkgname.html | tail -1 | grep -o '[0-9].*[0-9]'`
	fi
	eval $_output="'$version'"
}

#--------------------------------------------------------------------------
# netfilter_install():
# Download tarball, compile, install from Upstream. If missing dependence in configure phase,
# this function try to resolve by recursive call itself.
#
# Usage: <Pkgname> [Pkgname] ...
#--------------------------------------------------------------------------
# shellcheck disable=SC1083
netfilter_install()
{
	if [[ -z $1 ]];then
		echo "netfilter_install(): Need paramter!"
		return 1;
	else
		echo 'netfiter_install: expected install $@ packets'
	fi
local nf_pkgs="iptables
nftables
libnftnl
libnfnetlink
libnetfilter_acct
libnetfilter_log
libnetfilter_queue
libnetfilter_conntrack
libnetfilter_cttimeout
libnetfilter_cthelper
conntrack-tools
ipset
nfacct
ulogd
libmnl"
	# yum install common dependencies
	rpm -q git || yum install git -y
	rpm -q bzip2 || yum install bzip2 -y
	rpm -q gcc || yum install gcc -y
	rpm -q automake || yum install automake -y
	rpm -q bison || yum install bison -y
	rpm -q flex || yum install flex -y
	# Try yum install netfilter devel toolset first. If no rpm ready, *maybe* can be resolved in script later :)
	rpm -q libnfnetlink-devel || yum install libnfnetlink-devel -y
	rpm -q libmnl-devel || yum install libmnl-devel -y
	rpm -q libnetfilter_conntrack-devel || yum install libnetfilter_conntrack-devel -y

	until [[ -z $1 ]];do
		local name=$1; shift
		# Only install packet in
		[[ "$nf_pkgs" =~ .*$name.* ]] || continue;
		# find proper package version
		case `uname -r` in
			*el6*) release=RHEL6;;
			*el7*) release=RHEL7;;
			*el8*) release=RHEL8;;
			*el9*) release=RHEL9;;
			*) release=Other;;
		esac
		local Ver
		find_proper_version $name $release Ver
		wget --no-check-certificate http://www.netfilter.org/projects/${name}/files/${name}-${Ver}.tar.bz2 || \
			{ echo "Download ${name}-${Ver}.tar.bz2 fail"; return 2; }
		tar jxf ${name}-${Ver}.tar.bz2
		local retry=true
		while $retry;do
			echo ""
			echo ""
			echo "---------- Try to installing ${name}-${Ver}... ----------------"
			echo ""
			echo ""
			cd ${name}-${Ver}
			export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
			./configure --build=$(rpm --eval %{_host}) 2>&1 | tee $name.configure.log; [[ ${PIPESTATUS[1]} -eq 0 ]] && make && make install && { left=( ${left[@]#$name} ); retry=false;cd $WORK_PATH; }||\
			{ # handle "No package found error"
				tmp=`grep "No package" $name.configure.log` || { echo "netfilter_install: Can't handle error"; retry=false; return 1; } && \
				{ cd $WORK_PATH; netfilter_install `{ echo $nf_pkgs; eval echo $tmp; } |tr " " "\n"|sort | uniq -d`; }
			}
		done
	done
}

ipvsadm_install()
{
	which ipvsadm && return 0;

	rpm -q libnl3-devel || yum install libnl3-devel -y
	rpm -q popt-devel || yum install popt-devel -y
	wget https://mirrors.edge.kernel.org/pub/linux/utils/kernel/ipvsadm -O ipvsadm.html || \
	{ echo "connect to mirrors.edge.kernel.org fail"; return 2; }
	local version=`grep -Po "ipvsadm.*?.tar" ipvsadm.html |tail -1 |grep -o '[0-9].*[0-9]'`

	wget https://mirrors.edge.kernel.org/pub/linux/utils/kernel/ipvsadm/ipvsadm-1.31.tar.xz || \
	{ echo "Download ipvs-${version}.tar.xz fail"; return 2; }
	tar xf ipvsadm-$version.tar.xz
	pushd ipvsadm-$version
	make && make install
	popd
	which ipvsadm && left=( ${left[@]#ipvsadm} )
}

install_dependence()
{
	local _pkg
	for _pkg in "${dependences[@]}"
	do
	    yum -y install ${_pkg} || left+=( "$_pkg" )
	done
	[[ ${#left[*]} -ne 0 ]] && echo "Packege ${left[*]} need to be installed..."

	# Install the tools that failed with yum.
	# shellcheck disable=SC2048
	netfilter_install ${left[*]}
	[[ "${left[*]}" =~ .*ipvsadm.* ]] && ipvsadm_install
	# Expect nothing left to install
	[[ ${#left[*]} -ne 0 ]] && return 1;
}

4or6()
{
	if [[ $1 =~ .*:.* ]];then
	    echo "6"
	else
	    echo "4"
	fi
}

netfilter_rules_clean()
{
	echo ":: [    LOG    ] :: xtables rules clean"
	local xtables=""; local table=""; local chain="";
	for xtables in ebtables arptables iptables ip6tables; do
		$xtables --version > /dev/null 2>&1 || continue
		for table in filter nat mangle raw security broute; do
			$xtables -t $table -F > /dev/null 2>&1
			$xtables -t $table -X > /dev/null 2>&1
			for chain in INPUT OUTPUT PREROUTING FORWARD POSTROUTING BROUTING; do
				$xtables -t $table -P $chain ACCEPT >/dev/null 2>&1
			done
		done
	done
	echo ":: [    LOG    ] :: nft rules clean"
	nft --version > /dev/null 2>&1 && {
	local line=""
	nft list tables | while read line; do
		nft delete $line
		done
	}
	echo ":: [    LOG    ] :: ipset rules clean"
	ipset --version > /dev/null 2>&1 && ipset destroy
	echo ":: [    LOG    ] :: ipvsadm rules clean"
	ipvsadm --version > /dev/null 2>&1 && ipvsadm -C
	return 0
}
export -f netfilter_rules_clean

do_clean()
{
	for ns in client router server
	do
		ip netns |grep $ns && { \
		echo "netfilter_rules_clean" | ip netns exec $ns bash;
		ip netns del $ns; \
		}
	done
}

do_check()
{
	local ret=0
	ip netns exec client ping -W 40 -$(4or6 $ip_s) -I c_r $ip_s -c 5 -i 0.2 || { ret=1; }
	ip netns exec server ping -W 40 -$(4or6 $ip_c) -I s_r $ip_c -c 5 -i 0.2 || { ret=1; }
	return $ret
}

do_setup()
{
	set -x
	do_clean
	local i
	for i in client router server;do
	    ip netns add $i
	done

	if [[ "$1x" == "ipv6x" ]];then
		ip netns exec router sysctl -w net.ipv6.conf.all.forwarding=1
		ip_c=2001:db8:ffff:21::1
		ip_s=2001:db8:ffff:22::2
		ip_rc=2001:db8:ffff:21::fffe
		ip_rs=2001:db8:ffff:22::fffe
		N=64
		nodad=nodad
	elif [[ "$1x" == "ipv4x" ]];then
		ip netns exec router sysctl -w net.ipv4.ip_forward=1
		ip_c=10.167.1.1
		ip_s=10.167.2.2
		ip_rc=10.167.1.254
		ip_rs=10.167.2.254
		unset nodad
		N=24
	else
		set +x
		return 1;
	fi

	ip -d -n router -b /dev/stdin <<-EOF
		link add name r_c type veth peer name c_r netns client
		link add name r_s type veth peer name s_r netns server
		link set r_c up
		link set r_s up
		addr add $ip_rc/$N dev r_c $nodad
		addr add $ip_rs/$N dev r_s $nodad
		link set lo up
	EOF

	ip -d -n server -b /dev/stdin <<-EOF
		addr add $ip_s/$N dev s_r $nodad
		link set s_r up
		route add default via $ip_rs dev s_r
		link set lo up
	EOF

	ip -d -n client -b /dev/stdin <<-EOF
		addr add $ip_c/$N dev c_r $nodad
		link set c_r up
		route add default via $ip_rc dev c_r
		link set lo up
	EOF

	for i in tx rx tx-sctp-segmentation; do
		ip netns exec client ethtool -K c_r $i off
		ip netns exec server ethtool -K s_r $i off
	done 1>/dev/null 2>/dev/null

	sleep 2
	set +x
	do_check
}

run()
{
	local ns=$1; shift;
	# shellcheck disable=SC2124
	local cmd=$@;
	if [[ "$cmd" =~ "NoCheck" ]];then
		cmd=${cmd//NoCheck/}
		rlRun "ip netns exec $ns $cmd" 0-255 "NoCheck"
	elif [[ "$cmd" =~ "assert_fail" ]];then
		cmd=${cmd//assert_fail/}
		rlRun "ip netns exec $ns $cmd" 1-255 "assert_fail"
	else
		rlRun "ip netns exec $ns $cmd" 0
	fi
}
