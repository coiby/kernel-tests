#!/bin/bash

function rhel6_fatal_issues()
{
	# Bug 1710149 - fs/binfmt_misc.c: do not allow offset overflow
	osver_in_range "600" "611" && tskip "binfmt_misc01" fatal
	# Bug 1551908 - CVE-2018-5803 kernel: Missing length check of payload in net/sctp
	kernel_in_range "0" "2.6.32-751.el6" && tskip "cve-2018-5803" fatal
	# Bug 1438999 - CVE-2017-2671 kernel: ping socket / AF_LLC connect() sin_family race [rhel-6.10]
	kernel_in_range "0" "2.6.32-702.el6" && tskip "cve-2017-2671" fatal
	# Bug 1293402 - kernel: User triggerable crash from race between key read and ...
	kernel_in_range "0" "2.6.32-600.el6" && tskip "cve-2015-7550 keyctl02.*" fatal
	# Bug 1273463 - CVE-2015-7872 kernel: Using request_key() or keyctl request2 ...
	kernel_in_range "0" "2.6.32-585.el6" && tskip "keyctl03.*" fatal
	# kernel BUG at kernel/cred.c:97!
	osver_in_range "600" "609" && tskip "cve-2015-3290" fatal
	# Bug 1453183 - NULL ptr deref at follow_huge_addr+0x78/0x100
	osver_in_range "600" "611" && tskip "move_pages12.*" fatal
	# Bug 1490917 - CVE-2017-6951 kernel: NULL pointer dereference in keyring_search_aux function [rhel-6.10]
	osver_in_range "600" "611" && tskip "cve-2017-6951 request_key05" fatal
	# Bug 1498365 - CVE-2017-12192 kernel: NULL pointer dereference due to KEYCTL_READ
	osver_in_range "600" "611" && tskip "keyctl07 cve-2017-12192" fatal
	# Bug 1446569 - CVE-2016-9604 kernel: security: The built-in keyrings for security tokens can be joined as
	osver_in_range "600" "611" && tskip "cve-2016-9604" fatal
	# Bug 1450157 - CVE-2017-7472 kernel: keyctl_set_reqkey_keyring() leaks thread keyrings [rhel-6.10]
	osver_in_range "600" "611" && tskip "cve-2017-7472" fatal
	# Bug 1502909 - CVE-2017-15274 kernel: dereferencing NULL payload with nonzero length [rhel-6.10]
	osver_in_range "600" "611" && tskip "cve-2017-15274" fatal
	# Bug 1558845 - LTP fork05 reports 'BUG: unable to handle kernel paging request at XXX
	osver_in_range "600" "611" && tskip "fork05.*" fatal
	# Bug 1560398 - LTP modify_ldt02 causes panic 'BUG: unable to handle kernel paging request at XXX'
	osver_in_range "600" "611" && tskip "modify_ldt02.*" fatal
	# Bug 1543261 - CVE-2017-17807 kernel: Missing permissions check for request_key()
	osver_in_range "600" "611" && tskip "request_key04 cve-2017-17807" fatal
	# Bug 1579128 - sched/sysctl: Check user input value of sysctl_sched_time_avg
	osver_in_range "600" "611" && tskip "sysctl01.*" fatal
	# RHELTEST-1405: distribution/ltp/generic: VMMTIER1 mmap21_*__with_dmesg_entry "mmap21: command not found"
	osver_in_range "600" "611" && tskip "mmap21*" fatal
}

function rhel6_unfix_issues()
{
	# Bug 1653138 - remap_file_pages() return success in use after free of shm file
	osver_in_range "600" "611" && tskip "shmctl05" unfix
	# Bug 1537384 - KEYS: Disallow keyrings beginning with '.' to be joined as session keyrings
	osver_in_range "600" "611" && tskip "keyctl08" unfix
	# Bug 1537371 - KEYS: prevent creating a different user's keyrings
	osver_in_range "600" "611" && tskip "add_key03" unfix
	# Bug 1477055 - add_key02.c:99: FAIL: unexpected error with key type 'user': EINVAL
	osver_in_range "600" "611" && tskip "add_key02" unfix
	# Bug 1323048 - Page fault is not avoidable by using madvise...
	osver_in_range "600" "611" && tskip "madvise06" unfix
	# disable signal06 until we backport df24fb859a4e200d, 66463db4fc5605d51c7bb
	osver_in_range "600" "611" && tskip "signal06" unfix
	# Bug 1413025 - avc: denied { write } for pid=11089
	osver_in_range "600" "611" && tskip "quotactl01" unfix
	# Bug 1412044 - sctp: fix -ENOMEM result with invalid
	osver_in_range "600" "611" && tskip "sendto02" unfix
	# Bug 1455546 - [RHEL6.9][kernel] LTP recvmsg03 test hangs
	osver_in_range "600" "611" && tskip "recvmsg03.*" unfix
	# Bug 1490308 - [LTP keyctl04] fix keyctl_set_reqkey_keyring() to not leak thread keyrings
	osver_in_range "600" "611" && tskip "keyctl04" unfix
	# Bug 1491136 - [LTP cve-2017-5669] test for "Fix shmat mmap nil-page protection" fails
	osver_in_range "600" "611" && tskip "cve-2017-5669 shmat03" unfix
	#Bug 1652855 - LTP fcntl33 fcntl33_64 report FAIL: fcntl() downgraded lease when not read-only
	osver_in_range "600" "611" && tskip "fcntl33 fcntl33_64" unfix
	# Bug 1461342 - clock_adjtime(CLOCK_REALTIME) doesn't return current timex data
	osver_in_range "600" "611" && tskip "clock_adjtime01 clock_adjtime02" unfix
	# Bug 1059782 - backport numa: add a sysctl for numa_balancing
	osver_in_range "600" "611" && tskip "migrate_pages02" unfix
	# Bug 1610958 kernel: out-of-bounds access in the show_timer function in kernel/time/posix-timers.c
	tskip "timer_create03" unfix
	tskip "quotactl06" unfix
}

function rhel6_fixed_issues()
{
	# disable mlock03, it has been marked as broken on RHEL6
	tskip "mlock03" fixed
	# Bug 1193250 - FUTEX_WAKE may fail to wake waiters on...
	kernel_in_range "0" "2.6.32-555.el6" && tskip "futex_wake04" fixed
	# Bug 848316 - [hugetblfs]Attempt to mmap into highmem...
	kernel_in_range "0" "2.6.32-449.el6" && is_arch "ppc64" && tskip "mmap15" fixed
	# Bug 1205014 - vfs: fix data corruption when blocksize...
	kernel_in_range "0" "2.6.32-622.el6" && tskip "mmap16" fixed
	# Bug 862177 - [RHEL6] readahead not behaving as expected
	kernel_in_range "0" "2.6.32-465.el6" && tskip "readahead02.*" fixed
	# Bug 815891 - fork incorrectly succeeds when virtual...
	kernel_in_range "0" "2.6.32-304.el6" && tskip "fork14" fixed
	# disable vma testcases because of Bug 725855, for <RHEL6.4
	kernel_in_range "0" "2.6.32-279.el6" && tskip "vma0.*" fixed
	# disable gethostbyname_r01, GHOST glibc CVE-2015-0235
	pkg_in_range glibc "0" "2.18" && tskip "gethostbyname_r01" fixed
	# Bug 822731 - CVE-2012-3430 kernel: recv{from,msg}() on an rds socket can leak kernel memory [rhel-6.4]
	kernel_in_range "0" "2.6.32-294.el6" && tskip "recvmsg03.*" fixed
	# disable getrusage04 because bug 690998 is not in RHEL 6.0-z
	kernel_in_range "0" "2.6.32-131.0.5.el6" && tskip "getrusage04.*" fixed
	# Bug 789238 - [FJ6.2 Bug]: malloc() deadlock in case of allocation...
	pkg_in_range "glibc" "0" "2.12-1.68.el6" && tskip "mallocstress" fixed
	# Bug 1547587 - CVE-2018-6927 kernel: Integer overflow in futex.c:futux_requeue can lead to denial
	osver_in_range "600" "611" && tskip "cve-2018-6927 futex_cmp_requeue02" fixed
}

function rhel6_knownissue_filter()
{
	rhel6_fatal_issues;
	rhel6_unfix_issues;
	rhel6_fixed_issues;

	if is_zstream; then
		# Bug 1455612 - CVE-2017-8890 kernel: Double free in the inet_csk_clone_lock function in
		kernel_in_range "0" "2.6.32-754.0" && tskip "cve-2017-8890 accept02" fixed
		# Bug 1610958 (CVE-2017-18344) - CVE-2017-18344 kernel: out-of-bounds access in the show_timer
		kernel_in_range "0" "2.6.32-754.999" && tskip "cve--2017-18344 timer_create03" fixed
	fi
}
