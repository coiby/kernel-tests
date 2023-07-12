#!/bin/bash

function rhel7_fatal_issues()
{
	# Bug 1708066 - fs/binfmt_misc.c: do not allow offset overflow
	kernel_in_range "0" "3.10.0-1063.el7" && tskip "binfmt_misc01" fatal
	# Bug 1551906 - CVE-2018-5803 kernel: Missing length check of payload in net/sctp
	kernel_in_range "0" "3.10.0-871.el7" && tskip "cve-2018-5803" fatal
	# Bug 1498371 - CVE-2017-12192 kernel: NULL pointer dereference due to KEYCTL_READ
	kernel_in_range "0" "3.10.0-794.el7" && tskip "keyctl07 cve-2017-12192" fatal
	# Bug 1438998 - CVE-2017-2671 kernel: ping socket / AF_LLC connect() sin_family race
	kernel_in_range "0" "3.10.0-647.el7" && tskip "cve-2017-2671" fatal
	# Bug 1502625 - CVE-2017-12193 kernel: Null pointer dereference due to incorrect node-splitting
	kernel_in_range "0" "3.10.0-794.el7" && tskip "cve-2017-12193 add_key04" fatal
	# Bug 1579131 - sched/sysctl: Check user input value of sysctl_sched_time_avg
	osver_in_range "700" "707" && tskip "sysctl01.*" fatal
	# Bug 1464851 - kernel panic when ran ltp syscalls add_key02 on RHEL7.4
	kernel_in_range "0" "3.10.0-794.el7" && tskip "add_key02 cve-2017-15274" fatal
	# Bug 1461637 - [ltp/msgctl10] BUG: unable to handle kernel paging request at ffff8800abe4a5a0
	kernel_in_range "0" "3.10.0-957.el7" && tskip "msgctl10" fatal
	# Bug 1266759 - [s390x] ltp/futex_wake04.c cause system hang
	kernel_in_range "0" "3.10.0-957.el7" && is_arch "s390x" && tskip "futex_wake04" fatal
	# futex_wake04 hangs 7.0z
	kernel_in_range "0" "3.10.0-229.el7" && tskip "futex_wake04" fatal
	# Bug 1276398 - parallel memory allocation with numa balancing...
	[ $(free -g | grep Mem | awk '{print $2}') -gt 512 ] && \
		kernel_in_range "0" "3.10.0-436.el7" && tskip "mtest0.*" fatal
	# Bug 1256718 - Unable to handle kernel paging request for data in vmem_map
	kernel_in_range "0" "3.10.0-323.el7" && tskip "rwtest03.*" fatal
	# Bug 1247436 - BUG: soft lockup - CPU#3 stuck for 22s! [inotify06:51229]
	kernel_in_range "0" "3.10.0-320.el7" && tskip "inotify06.*" fatal
	# BUG: Bad page state in process msgctl11  pfn:3940e
	kernel_in_range "3.10.0-229.el7" "3.10.0-514.el7" && tskip "msgctl11" fatal
	# Bug 1481114 - [LTP fanotify07] kernel hangs while testing fanotify permission event destruction
	kernel_in_range "0" "3.10.0-810.el7" && tskip "fanotify07" fatal
	# Bug 1543262 - CVE-2017-17807 kernel: Missing permissions check for request_key()
	osver_in_range "700" "708" && tskip "request_key04 cve-2017-17807" fatal
	# Bug TBD - needs investigation: fallocate05 fails on ppc64/ppc64le
	is_arch "ppc64" && tskip "fallocate05" fatal
	is_arch "ppc64le" && tskip "fallocate05" fatal
	# Bug 1503242 - Backport keyring fixes
	kernel_in_range "0" "3.10.0-794.el7" && tskip "request_key03 cve-2017-15951 cve-2017-15299" fatal
	# Bug 1422368 - kernel: Off-by-one error in selinux_setprocattr
	kernel_in_range "0" "3.10.0-584.el7" && tskip "cve-2017-2618" fatal
	# Bug 1805590 - [FJ7.8 Bug]: system crash happened due to NULL pointer dereference at slip_write_wakeup()
	osver_in_range "700" "710" && tskip "pty03" fatal
}

function rhel7_unfix_issues()
{
	# skip madvise06 because of known issue:
	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/742#note_1039619667
	osver_in_range "700" "711" && tskip "madvise06" unfix
	# Bug 1543262 - CVE-2017-17807 kernel: Missing permissions check for request_key()
	osver_in_range "700" "709" && tskip "request_key04 cve-2017-17807" unfix
	# Bug 1688067 - [xfstests]: copy_file_range cause corruption on rhel-7
	osver_in_range "707" "710" && tskip "copy_file_range01" unfix
	# Bug 1708078 - cve-2017-17806 crypto: hmac - require that the underlying hash algorithm is unkeyed
	osver_in_range "700" "708" && tskip "af_alg01 cve-2017-17806" unfix
	# Bug 1708089 - crypto: af_alg - consolidation * of duplicate code
	osver_in_range "700" "710" && tskip "af_alg02 cve-2017-17805" unfix
	# Bug 1672242 - clash between linux/in.h and netinet/in.h
	osver_in_range "700" "708" && tskip "setsockopt03 cve-2016-4997" unfix
	# Bug 1639345 - [RHEL-7.7] fsnotify: fix ignore mask logic in fsnotify
	osver_in_range "700" "708" && tskip "fanotify10" unfix
	# Bug 1666604 - shmat returned EACCES when mapping the nil page
	osver_in_range "700" "711" && tskip "shmat03 cve-2017-5669" unfix
	# Bug 1666588 - getrlimit03.c:121: FAIL: __NR_prlimit64(0) had rlim_cur = ffffffffffffffff but __NR_getrlimit(0) had rlim_cur = ffffffffffffffff
	osver_in_range "700" "708" && is_arch "s390x"&& tskip "getrlimit03" unfix
	# Bug 1593435 - ppc64: kt1lite getrandom02 test failure reported
	osver_in_range "705" "707" && is_arch "ppc64" && tskip "getrandom02" unfix
	# Bug 1593435 - ppc64: kt1lite getrandom02 test failure reported
	osver_in_range "705" "707" && is_arch "ppc64le" && tskip "getrandom02" unfix
	# without this kernel commit "pipe: fix limit checking in alloc_pipe_info()"
	osver_in_range "700" "705" && is_arch "ppc64le" && tskip "pipe2_04" unfix
	# Bug 1185242 - Corruption with O_DIRECT and unaligned user buffers
	tskip "dma_thread_diotest" unfix
	# disable sysctl tests -> RHEL7 does not support these
	tskip "sysctl" unfix
	# Bug 1431926 - CVE-2016-10044 kernel: aio_mount function does not properly restrict execute access
	tskip "cve-2016-10044" unfix
	# Bug 1760639 - rhel7 timer_create: alarmtimer return wrong errno, on RTC-less system, s390x, ppc64
	! is_arch "x86_64" && osver_in_range "700" "709" && tskip "timer_create01" unfix
	# Bug 1726896 - mm: fix race on soft-offlining free huge pages
	osver_in_range "700" "710" && tskip "move_pages12" unfix
	# Bug 1715363 [RHEL-7 VFS][LTP copy_file_range02] deny non regular files for copy_file_range
	tskip "copy_file_range02" unfix
	# Bug 1820405 - KEYS: allow reaching the keys quotas exactly
	tskip "add_key05" unfix
	# Bug 1826030 (CVE-2020-11494) - CVE-2020-11494 kernel: transmission of uninitialized data allows attackers to read sensitive information
	tskip "pty04 cve-2020-11494" unfix
	# Bug 1832099 - fanotify: fix merging marks masks with FAN_ONDIR
	tskip "fanotify09" unfix
	# A xfs failure
	tskip "fallocate06" unfix
	# thp04: rhel7 missing commit 8310d48b125d
	osver_in_range "700" "710" && tskip "thp04 cve-2017-1000405" unfix
	# ptrace08: rhel7 missing 27747f8bc355
	osver_in_range "700" "710" && tskip "ptrace08 cve-2018-1000199" unfix
	# Bug 1597759 - kernel: Integer overflow in kernel/time/posix-timers.c
	osver_in_range "700" "710" && tskip "timer_settime03 cve-2018-12896" unfix
	# sched_rr_get_interval01: rhel7 missing 975e155ed873
	osver_in_range "700" "710" && tskip "sched_rr_get_interval01" unfix
	# timer_settime01: rhel7 missing e86fea764991
	osver_in_range "708" "710" && tskip "timer_settime01" unfix
	# Bug 1579402 - SAP RHEL 7 Feature: sysvipc: introduce STAT_ANY commands
	osver_in_range "702" "705" && tskip "msgctl06" unfix
	# Bug 1912670 - semctl SEM_STAT_ANY fails to pass the buffer specified by the caller to the kernel
	osver_in_range "702" "710" && tskip "semctl09" unfix
	# missing linux patch bd14406b78e6
	osver_in_range "700" "710" && tskip "ptrace10" unfix
	# Bug 1843799 - ltp xfs quotactl07 fail
	osver_in_range "700" "710" && tskip "quotactl07" unfix
	# Missing commit dd83c161fbcc in RHEL7
	osver_in_range "700" "710" && tskip "wait403" unfix
	# Missing commit 39d637af5aa7, 032146cda855 in RHEL7
	osver_in_range "700" "710" && tskip "finit_module02" unfix
	# Missing commit 7e08da50cf70 in RHEL7
	osver_in_range "700" "710" && tskip "quotactl06" unfix
	# wontfix bz1366788 in RHEL7 - Missing commit 01ea173e103e ("xfs: fix up non-directory creation in SGID directories") in RHEL7
	tskip "creat09" unfix
	# Bug 1432301 - [LTP] futex_wait05 1 TFAIL : futex_wait05.c:66: futex_wait() waited too long 211192us, expected 100010us
	tskip "futex_wait05" unfix
}

function rhel7_fixed_issues()
{
	# Bug 1652436 - fanotify: fix handling of events on child sub-directory
	osver_in_range "700" "708" && tskip "fanotify09" fixed
	# Bug 1597738 - [RHEL7.6]ltp fanotify09 test failed as missing patch of "fanotify: fix logic of events on child"
	kernel_in_range "0" "3.10.0-951.el7" && tskip "fanotify09" fixed
	# Bug 1633059 - [RHEL7.6]ltp syscalls/mlock203 test failed as missing patch "mm: mlock:
	kernel_in_range "0" "3.10.0-957.el7" && tskip "mlock203" fixed
	# Bug 1569921 - rhel7.5 regression in fsnotify, resulting in kernel panic or softlockup
	kernel_in_range "0" "3.10.0-896.el7"  && tskip "inotify09" fixed
	# Bug 1578750 - ovl: hash directory inodes for fsnotify
	osver_in_range "700" "707" && tskip "inotify07" fixed
	# Bug 1578751 - ovl: hash non-dir by lower inode for fsnotify
	osver_in_range "700" "707" && tskip "inotify08" fixed
	# Bug 1481118 - [LTP fcntl35] unprivileged user exceeds fs.pipe-max-size
	kernel_in_range "0" "3.10.0-951.el7" && tskip "fcntl35" fixed
	# Bug 1490308 - [LTP keyctl04] fix keyctl_set_reqkey_keyring() to not leak thread keyrings
	osver_in_range "700" "706" && tskip "keyctl04" fixed
	# Bug 1490314 - [LTP cve-2017-5669] test for "Fix shmat mmap nil-page protection" fails
	osver_in_range "700" "707" && tskip "cve-2017-5669" fixed
	# Bug 1450158 - CVE-2017-7472 kernel: keyctl_set_reqkey_keyring() leaks thread keyrings
	kernel_in_range "0" "3.10.0-794.el7" && tskip "cve-2017-7472" fixed
	# Bug 1421964 - spurious EMFILE errors from inotify_init
	kernel_in_range "0" "3.10.0-593.el7" && tskip "inotify06.*" fixed
	# Bug 1418182 - [FJ7.3 Bug]: The [X]GETNEXTQUOTA subcommand on quotactl systemcall returns a wrong value
	kernel_in_range "0" "3.10.0-592.el7" && tskip "quotactl03" fixed
	# Bug 1395538 - xfs: getxattr spuriously returns -ENOATTR due to setxattr race
	kernel_in_range "0" "3.10.0-561.el7" && tskip "getxattr04" fixed
	# Bug 1216957 - rsyslog restart pulls lots of older log entries again...
	kernel_in_range "3.10.0-229.el7" "3.10.0-693.el7" && tskip "syslog01" fixed
	# Bug 1385124 - CVE-2016-5195 kernel: Privilege escalation via MAP_PRIVATE
	kernel_in_range "0" "3.10.0-514.el7" && tskip "dirtyc0w" fixed
	# Bug 1183961 - fanotify: fix notification of groups with inode...
	kernel_in_range "0" "3.10.0-449.el7" && tskip "fanotify06" fixed
	# Bug 1293401 - kernel: User triggerable crash from race between key read and rey revoke [RHEL-7]
	kernel_in_range "0" "3.10.0-343.el7" && tskip "cve-2015-7550 keyctl02.*" fixed
	# Bug 1323048 - Page fault is not avoidable by using madvise...
	osver_in_range "700" "703" && tskip "madvise06" fixed
	# Bug 1232712 - x38_edac polluting logs: dmesg / systemd's journal
	kernel_in_range "0" "3.10.0-285.el7" && tskip "kmsg01" fixed
	# Bug 1162965 - Kernel panic - not syncing: Out of memory and no killable processes...
	kernel_in_range "0" "3.10.0-219.el7" && tskip "msgctl10" fixed
	# Bug 1121784 - Failed RT Signal delivery can corrupt FP registers
	kernel_in_range "0" "3.10.0-201.el7" && tskip "signal06" fixed
	# Bug 1156096 - ext4: rest of the update for rhel7.1
	kernel_in_range "0" "3.10.0-200.el7" && tskip "mmap16" fixed
	# Bug 1107774 - powerpc: 64bit sendfile is capped at 2GB
	kernel_in_range "0" "3.10.0-152.el7" && is_arch "ppc64" && tskip "sendfile09" fixed
	# Bug 1072385 - CVE-2014-8173 trinity hit BUG: unable to handle kernel...
	kernel_in_range "0" "3.10.0-148.el7" && tskip "madvise05" fixed
	# Bug 1092746 - system calls including getcwd and files in...
	kernel_in_range "0" "3.10.0-125.el7" && tskip "getcwd04" fixed
	# Bug 1351249 - [RHELSA-7.3] ltptest hits EWD at mtest01w
	kernel_in_range "0" "4.5.0-0.45.el7" && is_arch "aarch64" && tskip "mtest0.*" fixed
	# Bug 1352669 - [RHELSA-7.3] ltptest hits EWD at madvise06
	kernel_in_range "0" "4.5.0-0.45.el7" && is_arch "aarch64" && tskip "madvise06" fixed
	# Bug 1303001 - read() return -1 ENOMEM (Cannot allocate memory))...
	kernel_in_range "0" "4.5.0-0.rc3.27.el7" && is_arch "aarch64" && tskip "dio04 dio10" fixed
	# disable gethostbyname_r01, GHOST glibc CVE-2015-0235
	pkg_in_range glibc "0" "2.18" && tskip "gethostbyname_r01" fixed
	# Bug 1144516 - LTP profil01 test fails on RHELSA aarch64
	pkg_in_range "glibc" "0" "2.17-165.el7" && is_arch "aarch64" && tskip "profil01" fixed
	# Bug 1330705 - open() and openat() ignore 'mode' with O_TMPFILE
	pkg_in_range "glibc" "0" "2.17-159.el7.1" && tskip "open14 openat03"  fixed
	# Bug 1439264 - CVE-2017-6951 kernel: NULL pointer dereference in keyring_search_aux function [rhel-7.4]
	kernel_in_range "0" "3.10.0-686.el7" && tskip "cve-2017-6951 request_key05" fixed
	# Bug 1273465 - CVE-2015-7872 kernel: Using request_key() or keyctl request2 to get a kernel causes the key garbage collector to crash
	kernel_in_range "0" "3.10.0-332.el7" && tskip "keyctl03" fixed
	# Bug 1509152 - KEYS: return full count in keyring_read() if buffer is too small
	kernel_in_range "0" "3.10.0-794.el7" && tskip "keyctl06" fixed
	# Bug 1503242 - Backport keyring fixes
	kernel_in_range "0" "3.10.0-794.el7" && tskip "add_key03" fixed
	# Bug 1389309 - CVE-2016-9604 kernel: security: The built-in keyrings for security tokens can be joined as a session and then modified by the root user [rhel-7.4]
	kernel_in_range "0" "3.10.0-686.el7" && tskip "keyctl08 cve-2016-9604" fixed
	# Bug 1437404 - CVE-2017-7308 kernel: net/packet: overflow in check for priv area size
	kernel_in_range "0" "3.10.0-656.el7" && tskip "setsockopt02" fixed
	# Bug 1760639 rhel7 timer_create: alarmtimer return wrong errno, on RTC-less system, s390x, ppc64
	kernel_in_range "0" "3.10.0-1104.el7" && tskip "timer_delete01 timer_settime01 timer_settime02" fixed
	# Bug 1579402 - SAP RHEL 7 Feature: sysvipc: introduce STAT_ANY commands
	kernel_in_range "0" "3.10.0-911.el7" && tskip "shmctl04" fixed
}

function rhel7_knownissue_filter()
{
	rhel7_fatal_issues;
	rhel7_unfix_issues;
	rhel7_fixed_issues;

	if is_zstream; then
		# Bug 1797966 - [xfstests]: copy_file_range cause corruption on rhel-7 [rhel-7.6.z]
		osver_in_range "700" "710" && tskip "copy_file_range01 copy_file_range03" unfix
		# Bug 1441171 - CVE-2017-7308 kernel: net/packet: overflow in check for priv area size [rhel-7.3.z]
		kernel_in_range "3.10.0-514.21.1.el7" "3.10.0-514.999" && tback "setsockopt02"
		# Bug 1658607 - ltp/lite fallocate05 failing on RHEL-6.10
		# Skip <= 72z
		kernel_in_range "0" "3.10.0-327.9999" && tskip "fallocate05" fixed
		# Bug 1455609 - CVE-2017-8890 kernel: Double free in the inet_csk_clone_lock function in net/ipv4/inet_connection_sock.c [rhel-7.4]
		kernel_in_range "0" "3.10.0-693.0" && tskip "cve-2017-8890 accept02" fixed
		# Bug 1544612 (CVE-2018-6927) - CVE-2018-6927 kernel: Integer overflow in futex.c:futux_requeue can lead to denial of service or unspecified impact
		kernel_in_range "0" "3.10.0-862.0" && tskip "cve-2018-6927 futex_cmp_requeue02" fixed
		# Bug 1402013 (CVE-2016-9793) - CVE-2016-9793 kernel: Signed overflow for SO_{SND|RCV}BUFFORCE
		kernel_in_range "0" "3.10.0-327.9999" && tskip "cve-2016-9793 setsockopt04" fixed
		# fanotify06 new subcase skipped on zstream.
		tskip "fanotify06" fixed
		# Bug 1481136 (CVE-2017-10661) - CVE-2017-10661 kernel: Handling of might_cancel queueing is not properly pretected against race
		osver_in_range "700" "704" && tskip "timerfd_settime02" unfix
		# Bug 1589324 CVE-2018-1000204 kernel: Infoleak caused by incorrect handling of the SG_IO ioctl
		osver_in_range "700" "708" && tskip "ioctl_sg01" unfix
	fi
}
