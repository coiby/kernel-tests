#!/bin/bash

function rhel9_fatal_issues()
{
	# systemd oom policy will send SIGTERM to restraintd
	osver_in_range "900" "901" && tskip "oom0.*" fatal
	# BZ2026959, BZ2112284
	osver_in_range "900" "903" && is_arch "aarch64" && tskip "read_all_sys" fatal
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
	# Bug 2125133 - inotify12.c:85: TFAIL: Incorrect mask 2 in inotify fdinfo (expected 80000002)
	osver_in_range "900" "902" && tskip "inotify12" unfix
}

function rhel9_fixed_issues()
{
	# Bug 2035164 - [RHEL9] timerlat tracer cause ppc64le panic: BUG: Unable to handle kernel data access on read at 0x1fd4b0000
	kernel_in_range "0" "5.14.0-61.el9" && is_arch "ppc64le" && tskip "ftrace_stress_test" fixed
	# Bug 2038794 - Backport futex_waitv() from Linux 5.16
	kernel_in_range "0" "5.14.0-77.el9" && tskip "futex_waitv0.*" fixed
}

function rhel9_knownissue_filter()
{
	rhel9_fatal_issues;
	rhel9_unfix_issues;
	rhel9_fixed_issues;
}
