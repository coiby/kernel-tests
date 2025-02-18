#!/bin/bash

# Knownissue classification:
#
#   fatal: means the issue/bz caused by this testcase will block(system
#          panic or hang) our test. we suggest to skip it directly.
#
#   fixed: means the issue/bz caused by this testcase has already been
#          fixed in a specified kernel version. And the testcase only
#          failed but no system panic/hang, we suggest to skip it when
#          < fixed-kernel-version, or we can remark the test result as
#          KNOWN issue in log to avoid beaker report failure.
#
#   unfix: means the issue/bz caused by this testcase have NOT being
#          fixed in corresponding RHEL(BZ delay to next version) product
#          or it'll never get a chance to be fixed(BZ close as WONTFIX).
#          And the testcase only failed but no system panic/hang), we
#          suggest to skip it when <= unfix-rhel-version, or we can remark
#          the test result as KNOWN issue to avoid beaker report failure.
#
# Issue Note:
#      We'd better follow these principles to exlucde testcase:
#      1. Upstream kernel bug use its kernel-nvr ranges
#      2. RHEL kernel bug(fixed) use its kernel-nvr ranges
#      3. RHEL kernel bug(unfix) use distro exclustion first, then move
#         to kernel-nvr ranges once it has been fixed.
#      4. Userspace package bug use itself package-nvr ranges
#
# Added-by: Li Wang <liwang@redhat.com>

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")

. "$CDIR"/../include/kvercmp.sh				|| exit 1
. "$CDIR"/../include/knownissue/upstream_knownissue.sh	|| exit 1
. "$CDIR"/../include/knownissue/rhel_alt_knownissue.sh	|| exit 1
. "$CDIR"/../include/knownissue/rhel9_knownissue.sh	|| exit 1
. "$CDIR"/../include/knownissue/rhel8_knownissue.sh	|| exit 1
. "$CDIR"/../include/knownissue/rhel7_knownissue.sh	|| exit 1
. "$CDIR"/../include/knownissue/rhel6_knownissue.sh	|| exit 1
. "$CDIR"/../include/knownissue/rhel5_knownissue.sh	|| exit 1

cver=$(uname -r)

function is_fedora() { grep -iq "fedora" /etc/system-release; }
function is_rhel() { grep -iq "red hat enterprise linux" /etc/system-release; }
function is_centos() { grep -iq "CentOS" /etc/system-release; }
function is_autosd() { grep -iq "Automotive Stream Distribution release" /etc/system-release; }

# Identify OS release
if [ -r /etc/system-release ]; then
	# If system-release exists, we're on Fedora or RHEL6 or newer
	release=$(cat /etc/system-release)

	if is_fedora; then
		osver=$(echo "$release" | cut -d' ' -f3)
	elif is_rhel; then
		osver=$(echo "$release" | awk -F' ' '{print int(substr($6, 1,1))*100 + (int(substr($6,3,2)))}')
		if [ "$osver" == "0" ]; then
			# fallback for format in rhel <= 7
			osver=$(echo "$release" | awk -F' ' '{print int(substr($7, 1,1))*100 + (int(substr($7,3,2)))}')
		fi
	elif is_centos; then
		# CentOS Stream seems to contain only major release info
		osver=$(echo "$release" | awk -F' ' '{print int(substr($4, 1,1))*100}')
	elif is_autosd; then
		# Automotive seems same to CentOS contain only major release info
		osver=$(echo "$release" | awk -F' ' '{print int(substr($5, 1,1))*100}')
	fi
else
	# if we don't have system-release, use the old mechanism
	osver=0
fi


kn_fatal=${LTPDIR}/KNOWNISSUE_FATAL
kn_unfix=${LTPDIR}/KNOWNISSUE_UNFIX
kn_fixed=${LTPDIR}/KNOWNISSUE_FIXED
kn_issue=${LTPDIR}/KNOWNISSUE

function is_rhel5() { grep -q "release 5" /etc/redhat-release; }
function is_rhel6() { grep -q "release 6" /etc/redhat-release; }
function is_rhel7() { grep -q "release 7" /etc/redhat-release; }
function is_rhel8() { grep -q "release 8" /etc/redhat-release; }
function is_rhel9() { grep -q "release 9" /etc/redhat-release; }
function is_rhel_alt() { rpm -q --qf "%{sourcerpm}\n" -f "/boot/vmlinuz-$(uname -r)" | grep -q "alt"; }
function is_upstream() { uname -r | grep -q -v 'el[0-9]\|fc'; }
function is_arch() { [ "$(uname -m)" == "$1" ]; }
function is_zstream() { uname -r | awk -F. '{if (match($4, "[[:digit:]]") != 1) exit 1}'; }
function is_kvm()
{
	if command -v virt-what; then
		{ virt-what | grep -q 'kvm'; } && return 0
	fi
	return 1
}
function is_rt() { [ -f /sbin/kernel-is-rt ] && /sbin/kernel-is-rt; }
# osver_low <= $osver < osver_high
function osver_in_range() { ! is_upstream && { [ "$1" -le "$osver" ] && [ "$osver" -lt "$2" ]; } }

# kernel_low <= $cver < kernel_high
function kernel_in_range()
{
	kvercmp "$1" "$cver"
	if [ $kver_ret -le 0 ]; then
		kvercmp "$cver" "$2"
		if [ $kver_ret -lt 0 ]; then
			return 0
		fi
	fi
	return 1
}

# pkg_low <= $pkgver < pkg_high
function pkg_in_range()
{
	pkgver=$(rpm -qa "$1" | head -1 | sed 's/\(\w\+-\)//')
	kvercmp "$2" "$pkgver"
	if [ $kver_ret -le 0 ]; then
		kvercmp "$pkgver" "$3"
		if [ $kver_ret -lt 0 ]; then
			return 0
		fi
	fi
	return 1
}

# Usage: tskip "case1 case2 case3 ... caseN" fixed
function tskip()
{
	if echo "|fatal|fixed|unfix|" | grep -q "|$2|"; then
		for tcase in $1; do
			echo "$tcase" >> $(eval echo '${kn_'$2'}')
		done
	else
		echo "Error: parameter \"$2\" is incorrect."
		exit 1
	fi
}

# Usage: tback "case1 case2 case3 ... caseN"
# add back cases,like zstream fixed case
function tback()
{
	for tcase in $1; do
		sed -i "/\b$tcase\b/d" "${kn_fatal}" "${kn_unfix}" "${kn_fixed}"
	done
}

# Keep in mind that all known issues should have finite exclusion range, that
# will end in near future. So that these issues pop up again, once we move to
# new minor/upstream release. And we have chance to re-evaluate.
# For example:
# - kernel_in_range "0" "2.6.32-600.el6" -> FINE
# - kernel_in_range "0" "9999.9999.9999" -> PROBLEM, will be excluded forever
# - osver_in_range "600" "609" -> FINE
# - osver_in_range "600" "99999" -> PROBLEM, will be excluded forever
function knownissue_filter()
{
	# -------------------Common Issues ---------------------
	# skip OOM tests on large boxes since it takes too long
	[ "$(free -g | grep "^Mem:" | awk '{print $2}')" -gt 8 ] && tskip "oom0.*" fatal
	[ "$(free -g | grep "^Mem:" | awk '{print $2}')" -gt 64 ] && tskip "mtest01w" fatal
	[ "$(free -g | grep "^Mem:" | awk '{print $2}')" -gt 32 ] || cki_is_kernel_debug && tskip "ioctl_sg01" fatal
	# this case always make the beaker task abort with 'incrementing stop' msg
	tskip "min_free_kbytes" fatal
	# msgctl10 -> keeps triggerring OOM...(Bug 1162965?), msgctl11 -> too many pids
	# LTP-20180926 renamed msgctl08-11 to msgstress01-04, so skip msgstress03-04 too
	#     https://github.com/linux-test-project/ltp/commit/3e882e3e4c2d
	tskip "msgctl10 msgctl11 msgstress03 msgstress04" fatal
	# read_all_dev can trigger accidental reboots when reading /dev/watchdog
	# https://github.com/linux-test-project/ltp/issues/377
	tskip "read_all_dev" fatal
	# Bug 1534635 - CVE-2018-1000001 glibc: realpath() buffer underflow when getcwd()
	pkg_in_range "glibc" "0" "2.17-221.el7" && tskip "realpath01 cve-2018-1000001" fixed

	cki_is_kernel_debug && tskip "futex_cmp_requeue01 squashfs01" unfix

	# These test cases take too long to run on VMs
	cki_is_vm || cki_is_kernel_debug && tskip "fork14 setsockopt06 mtest06 pty03 writev03" fatal

	# permanent issue with this HW: https://bugzilla.redhat.com/show_bug.cgi?id=1975018
	{ hostname | grep -E "hpe-appollo-80|fujitsu-fx700" >/dev/null; } && tskip "rtc02" unfix

	# ----------------- NOTE: -----------------------------
	# we have split the knownissue's data from code, better
	# to add new issues in knownissue/* file from now on.
	is_upstream && upstream_knownissue_filter;
	is_rhel_alt && rhel_alt_knownissue_filter;
	is_rhel9 && rhel9_knownissue_filter;
	is_rhel8 && rhel8_knownissue_filter;
	is_rhel7 && rhel7_knownissue_filter;
	is_rhel6 && rhel6_knownissue_filter;
	is_rhel5 && rhel5_knownissue_filter;
}

function tcase_exclude()
{
	local config="$*"

	while read -r skip; do
		echo "Excluding $skip form LTP runtest file"
		sed -i "s/^\($skip\)/#disabled, \1/g" ${config}
	done
}

# Usage:    knownissue_exclude "all" "RHELKT1LITE"
#
# Parameter explanation:
#  "all"    - skip all of the knownissues on test system
#  "fatal"  - only skip the fatal knownissues, and mark the others
#             from 'FAIL' to 'KNOW' in test log
#  "none"   - none of the knownissues will be skiped, only change
#             from 'FAIL' to 'KNOW' in test log
function knownissue_exclude()
{
	local param=$1
	shift
	local runtest="$*"

	rm -f "${kn_fatal} ${kn_unfix} ${kn_fixed} ${kn_issue}"

	knownissue_filter

	case $param in
	  "all")
		[ -f "${kn_fatal}" ] && cat "${kn_fatal}" | tcase_exclude "${runtest}"
		[ -f "${kn_unfix}" ] && cat "${kn_unfix}" | tcase_exclude "${runtest}"
		[ -f "${kn_fixed}" ] && cat "${kn_fixed}" | tcase_exclude "${runtest}"
		;;
	"fatal")
		[ -f "${kn_fatal}" ] && cat "${kn_fatal}" | tcase_exclude "${runtest}"
		[ -f "${kn_unfix}" ] && cat "${kn_unfix}" >> "${kn_issue}"
		[ -f "${kn_fixed}" ] && cat "${kn_fixed}" >> "${kn_issue}"
		;;
	 "none")
		[ -f "${kn_fatal}" ] && cat "${kn_fatal}" >> "${kn_issue}"
		[ -f "${kn_unfix}" ] && cat "${kn_unfix}" >> "${kn_issue}"
		[ -f "${kn_fixed}" ] && cat "${kn_fixed}" >> "${kn_issue}"
		;;
	      *)
		echo "Error, parameter $1 is incorrect."
		;;
	esac
}
