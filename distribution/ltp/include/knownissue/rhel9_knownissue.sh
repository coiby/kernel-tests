#!/bin/bash

function rhel9_fatal_issues()
{
	# systemd oom policy will send SIGTERM to restraintd
	osver_in_range "900" "901" && tskip "oom0.*" fatal
	# BZ2026959, BZ2112284
	osver_in_range "900" "903" && is_arch "aarch64" && tskip "read_all_sys" fatal
	# Bug 2178947 - [RHEL9] kernel-rt-debug: BUG: MAX_LOCKDEP_CHAINS too low
	# Bug 2119055 - [rhel9] call trace qed_ptt_acquire+0x2b/0xd0 [qed] _qed_get_vport_stats+0x141/0x240 [qed]
	osver_in_range "900" "905" && tskip "read_all_sys" fatal
	# Bug 1984293 - RHEL9: kernel-rt: WARNING: possible circular locking dependency detected (raw_v6_hashinfo.lock->(softirq_ctrl.lock).lock->raw_v6_hashinfo.lock
	is_rt && cki_is_kernel_debug && osver_in_range "900" "902" && tskip "read_all_proc" fatal
}

function rhel9_unfix_issues()
{
	# https://bugzilla.redhat.com/show_bug.cgi?id=1913045#c24
	is_arch "aarch64" && tskip "ioctl_sg01" unfix
	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/536#note_896846475
	tskip "ioctl09" unfix
	# Bug 2090079 - inotify11.c:91: TFAIL: File 5579 opened after IN_DELETE
	osver_in_range "900" "902" && tskip "inotify11" unfix
	# Bug 2085824 - [RHEL-9.1] /ltp/lite madvise06.c:231: TFAIL: 7 pages were faulted out of 2 max 54
	osver_in_range "900" "902" && tskip "madvise06" unfix
	# Bug 2128900 - [FJ9.1 Bug]: xfs: setgid is not stripped after setting mask [xfstests: generic/697]
	osver_in_range "900" "903" && tskip "creat09 cve-2018-13405" unfix
	# Bug 2137802 - ltp commands df01 xfs failed
	osver_in_range "900" "903" && tskip "df01_sh" unfix
	# Bug 2120448 - [RHEL 9.0] LTP Test failure and crash at fork14 on Sapphire Rapids Platinum 8280+
	osver_in_range "900" "903" && tskip "fork14" unfix
	# Bug 2152548 (CVE-2022-4378) - CVE-2022-4378 kernel: a stack overflow in do_proc_dointvec and proc_skip_spaces
	osver_in_range "900" "904" && tskip "cve-2022-4378" unfix
	# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/1670
	is_rt && pkg_in_range "tuned" "2.19.0" "99" && tskip "numa_testcases" unfix
	# https://issues.redhat.com/browse/RHEL-8576 [RHEL-9.3.0] "stack_clash" LTP CVE test fails
	is_arch "x86_64" && osver_in_range "900" "905" && tskip "cve-2017-1000364 stack_clash" unfix
	# https://issues.redhat.com/browse/RHEL-5767 [RHEL9.3] ltp- fanotify14.c:286: TFAIL: fanotify_mark(fanotify_fd, 0x00000001 | tc->mark.flags, tc->mask.flags, dirfd, path) expected EINVAL: EACCES (13)
	osver_in_range "900" "905" && tskip "fanotify14" unfix
}

function rhel9_fixed_issues()
{
	# Bug 2035164 - [RHEL9] timerlat tracer cause ppc64le panic: BUG: Unable to handle kernel data access on read at 0x1fd4b0000
	kernel_in_range "0" "5.14.0-61.el9" && is_arch "ppc64le" && tskip "ftrace_stress_test" fixed
	# Bug 2038794 - Backport futex_waitv() from Linux 5.16
	kernel_in_range "0" "5.14.0-77.el9" && tskip "futex_waitv0.*" fixed
	# Bug 2090079 - inotify11.c:91: TFAIL: File 5579 opened after IN_DELETE
	kernel_in_range "0" "5.14.0-176.el9" && tskip "inotify11" fixed
	# Bug 2125133 - inotify12.c:85: TFAIL: Incorrect mask 2 in inotify fdinfo (expected 80000002)
	kernel_in_range "0" "5.14.0-176.el9" && tskip "inotify12" fixed
	# Bug 2097485 - [RHEL-9.1] execve06_child.c:15: TFAIL: argc is 0, expected 1
	kernel_in_range "0" "5.14.0-122.el9" && tskip "execve06" fixed
	# Bug 2128900 - [FJ9.1 Bug]: xfs: setgid is not stripped after setting mask [xfstests: generic/697]
	kernel_in_range "0" "5.14.0-236.el9" && tskip "openat04" fixed
}

function rhel9_knownissue_filter()
{
	rhel9_fatal_issues;
	rhel9_unfix_issues;
	rhel9_fixed_issues;
}
