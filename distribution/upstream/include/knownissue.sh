#!/bin/bash

# Description:
#
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

. ../include/kvercmp.sh  || exit 1

cver=$(uname -r)

# Identify OS release
if [ -r /etc/system-release-cpe ]; then
	# If system-release-cpe exists, we're on Fedora or RHEL6 or newer
	cpe=$(cat /etc/system-release-cpe)
	osflav=$(echo $cpe | cut -d: -f4)

	case $osflav in
		  fedora)
			osver=$(echo $cpe | cut -d: -f5)
			;;

	enterprise_linux)
			osver=$(echo $cpe | awk -F: '{print int(substr($5, 1,1))*100 + (int(substr($5,3,2)))}')
			;;
	esac
else
	# if we don't have system-release-cpe, use the old mechanism
	osver=0
fi

kn_fatal=${LTPDIR}/KNOWNISSUE_FATAL
kn_unfix=${LTPDIR}/KNOWNISSUE_UNFIX
kn_fixed=${LTPDIR}/KNOWNISSUE_FIXED
kn_issue=${LTPDIR}/KNOWNISSUE

function is_rhel8() { grep -q "release 8" /etc/redhat-release; }
function is_fedora() { grep -q "Fedora" /etc/redhat-release; }
function is_upstream() { uname -r | grep -q -v 'el[0-9]\|fc'; }
function is_arch() { [ "$(uname -m)" == "$1" ]; }
# osver_low <= $osver < osver_high
function osver_in_range() { ! is_upstream && [[ "$1" -le "$osver" && "$osver" -lt "$2" ]]; }

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
	pkgver=$(rpm -qa $1 | head -1 | sed 's/\(\w\+-\)//')
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
	# skip OOM tests on large boxes since it takes too long
	[ $(free -g | grep "^Mem:" | awk '{print $2}') -gt 8 ] && tskip "oom0.*" fatal
	[ $(free -g | grep "^Mem:" | awk '{print $2}') -gt 32 ] || cki_is_kernel_debug && tskip "ioctl_sg01" fatal

	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/1052#note_922133965
	# + https://lists.linux.it/pipermail/ltp/2022-March/028110.html
	tskip "waitid10" unfix
	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/797
	# + https://github.com/linux-test-project/ltp/commit/ba50e6f93c944617cb4c94bf20a597b204dc275c
	kernel_in_range "4.14.0" "5.15.0" && tskip "finit_module02" unfix
	# cfs_bandwidth01 failed on aarch64 because of kernel bug
	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/654
	# + https://bugzilla.redhat.com/show_bug.cgi?id=2000839
	# + https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=2630cde26711dab0d0b56a8be1616475be646d13
	kernel_in_range "5.0.0" "5.15" && tskip cfs_bandwidth01 unfix
	# skip OOM tests on large boxes since it takes too long
	[ $(free -g | grep "^Mem:" | awk '{print $2}') -gt 8 ] && tskip "ioctl_sg01 oom0.*" fatal
	# New test cve-2021-3609 (can_bcm01) caused panic, which has been fixed
	# in 5.14-rc1
	kernel_in_range "5.0.0" "5.14" && tskip "cve-2021-3609 can_bcm01" fatal
	# shmget02 failed on ppc64le because of ENOENT
	# Issue: https://github.com/linux-test-project/ltp/issues/853
	is_arch "ppc64le" && tskip "shmget02" unfix
	# msgget/shmget03 failed unexpectedly: ENOSPC (28)
	# Issue: https://github.com/linux-test-project/ltp/issues/842
	tskip "msgget03" unfix
	tskip "shmget03" unfix
	# copy_file_range02 is a new unstable test case and changes too frequently
	tskip "copy_file_range02" unfix
	# Issue: https://github.com/linux-test-project/ltp/issues/799
	tskip "clock_gettime04" unfix
	# Issue TBD
	tskip "madvise09" fatal
	# Issue TBD
	tskip "memfd_create03" unfix
	# this case always make the beaker task abort with 'incrementing stop' msg
	tskip "min_free_kbytes" fatal
	# Issue TBD
	tskip "msgstress0.*" unfix
	# Issue TBD
	tskip "epoll_wait02" unfix
	# Issue TBD
	tskip "ftrace-stress-test" fatal
	# Issue TBD
	tskip "sync_file_range02" unfix
	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/536
	tskip "ioctl09" unfix
	# OOM tests result in oom errors killing the test harness
	tskip "oom.*" fatal
	# fs_fill test exceeds timeout, TBD adjust timeout settings
	tskip "fs_fill" unfix
	# Unable to load BPF programs on s390x/upstream kernels (FMK-1825)
	is_arch "s390x" && tskip "bpf_prog01 bpf_prog02" unfix
	# pty04 is unstable, see https://github.com/linux-test-project/ltp/issues/674
	tskip "pty04" unfix
	# https://lists.linux.it/pipermail/ltp/2020-June/017701.html
	tskip "ptrace08" unfix
	# [bug] parse_vdso.c is crashing on 5.8-rc5 s390x, because it wrongly reads nbucket as 0
	# https://lore.kernel.org/lkml/9927ed18c642db002e43afe5e36fb9c18c4f9495.1594811090.git.jstancek@redhat.com/
	is_arch "s390x" && tskip "clock_gettime04" unfix
	# Skip syslog tests, slowness of on some machines make all races more pronounced logs are not very useful for debugging.
	tskip "syslog.*" unfix
	# These tests are not suitable if there is overcommit for s390x guests
	is_arch "s390x" && tskip "mtest01 dio20 dio30 fallocate05 fallocate06 fork13 preadv203 preadv203_64 sendfile09 sendfile09_64" unfix
	# [bug] msgstress04 fills up >4GB data on conserver for ppc64le
	# https://lore.kernel.org/linux-block/491751.10128377.1599217585366.JavaMail.zimbra@redhat.com/T/#t
	is_arch "ppc64le" && tskip "msgstress04" fatal
	# Issue to be filed
	tskip "perf_event_open02" unfix
	# netns_breakns_ip_ipv6_netlink was re-written upstream, not yet stable
	tskip "netns_breakns_ip_ipv6_netlink netns_breakns_ns_exec_ipv6_netlink" unfix
	# Bug 1912670 - semctl SEM_STAT_ANY fails to pass the buffer specified by the caller to the kernel
	tskip "semctl09" unfix
	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/563#note_658789326
	tskip "mkswap01" unfix

	if is_rhel8; then
		# ------- unfix ---------
		# Bug 1734286 - mm: mempolicy: make mbind() return -EIO when MPOL_MF_STRICT is specified
		osver_in_range "800" "802" && tskip "mbind02" unfix
	fi

	# XXX: https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/541
	cki_is_vm && tskip "ksm*" unfix
	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/639
	cki_is_vm && tskip "msgstress03 msgstress04" fatal
	# http://lists.infradead.org/pipermail/linux-arm-kernel/2021-June/668228.html
	is_arch "aarch64" && tskip "read_all_sys" fatal
	cki_has_kernel_debug_flags && tskip "futex_cmp_requeue01" unfix

	# XXX: https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/680
	# skip "cve-2019-8912" because al_alg07 is fragile
	tskip "cve-2019-8912" unfix
}

function tcase_exclude()
{
	local config="$*"

	while read skip; do
		echo "Excluding $skip form LTP runtest file"
		sed -i 's/^\('$skip'\)/#disabled, \1/g' ${config}
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

	rm -f ${kn_fatal} ${kn_unfix} ${kn_fixed} ${kn_issue}

	knownissue_filter

	case $param in
	  "all")
		[ -f ${kn_fatal} ] && cat ${kn_fatal} | tcase_exclude ${runtest}
		[ -f ${kn_unfix} ] && cat ${kn_unfix} | tcase_exclude ${runtest}
		[ -f ${kn_fixed} ] && cat ${kn_fixed} | tcase_exclude ${runtest}
		;;
	"fatal")
		[ -f ${kn_fatal} ] && cat ${kn_fatal} | tcase_exclude ${runtest}
		[ -f ${kn_unfix} ] && cat ${kn_unfix} >> ${kn_issue}
		[ -f ${kn_fixed} ] && cat ${kn_fixed} >> ${kn_issue}
		;;
	 "none")
		[ -f ${kn_fatal} ] && cat ${kn_fatal} >> ${kn_issue}
		[ -f ${kn_unfix} ] && cat ${kn_unfix} >> ${kn_issue}
		[ -f ${kn_fixed} ] && cat ${kn_fixed} >> ${kn_issue}
		;;
	      *)
		echo "Error, parameter "$1" is incorrect."
		;;
	esac
}
