#!/bin/bash

function rhel_alt_fatal_issues()
{
	# Bug 1679243 - RHEL-ALT-7.6z: usage of stale vma in do_fault() can lead to a crash
	osver_in_range "700" "707" && is_arch "s390x" && tskip "mtest06" fatal
	# Bug 1402585 - kernel panic on split_huge_page_to_list() on Pegas
	# Bug 1383953 - WARNING: CPU: 4 PID: 33 at arch/x86/kernel/smp.c:125 native_smp_send_reschedule+0x3f/0x50
	# Bug 1405748 - [Pegas-7.4-20161213.n.2][PANIC] Kernel panic - not syncing: Out of memory and no killable processes...
	# kernel 4.8.0, 4.9.0, 4.10.0 and 4.11.0
	kernel_in_range "4.8.0-0.5.el7" "4.12.0-0.0.el7" && tskip "oom0.*" fatal
	# Bug 1481899 - Pegas1.0 Alpha [ P9 ZZ DD2 ]: machine crashes while running runltp.
	kernel_in_range "4.8.0-0.5.el7" "4.11.0-32.el7" && tskip "keyctl05" fatal
	# Bug 1519901 - WARNING: possible circular locking dependency detected
	is_arch "aarch64" && kernel_in_range "4.14.0-0.el7" "4.14.0-53.el7" && tskip "dynamic_debug01" fatal
	# Bug 1551905 - CVE-2018-5803 kernel-alt: kernel: Missing length check of payload in net/sctp
	kernel_in_range "0" "4.14.0-58.el7" && tskip "cve-2018-5803" fatal
	# Bug 1647199 - pty02 causes kernel panics on kernels older than 4.15, see upstream kernel commit 966031f340185
	tskip "pty02" fatal
	# Bug 1708066 - fs/binfmt_misc.c: do not allow offset overflow
	osver_in_range "700" "707" && tskip "binfmt_misc01" fatal
	# Bug 1875699 - CVE-2020-14386 kernel: memory corruption in net/packet/af_packet.c leads to elevation of privilege
	osver_in_range "700" "707" && tskip "cve-2020-14386 sendto03" fatal
}

function rhel_alt_unfix_issues()
{
	# http://lists.linux.it/pipermail/ltp/2017-January/003424.html
	kernel_in_range "4.8.0-rc6" "4.12" && tskip "utimensat01.*" unfix
	# sysfs syscall is deprecated and not implemented for aarch64 kernels
	# NOTE: sysfs syscall is unrelated to the sysfs filesystem, i.e., /sys
	is_arch "aarch64" && tskip "sysfs" unfix
	# ustat syscall is deprecated and not implemented for aarch64 kernels
	is_arch "aarch64" && tskip "ustat" unfix
	# Bug 1777554 - false positive with huge pages on aarch64
	# Note: this can be removed when pkey01 is fixed upstream
	#       http://lists.linux.it/pipermail/ltp/2019-December/014683.html
	is_arch "aarch64" && tskip "pkey01" unfix
	# Bug 1579402 - SAP RHEL 7 Feature: sysvipc: introduce STAT_ANY commands
	tskip "shmctl04" unfix
}

function rhel_alt_fixed_issues()
{
	# disable futex_wake04 until we fix Bug 1087896
	osver_in_range "700" "705" && is_arch "aarch64" && tskip "futex_wake04" fixed
	# Bug 1543265 - CVE-2017-17807 kernel-alt: kernel: Missing permissions check for request_key()
	osver_in_range "700" "708" && tskip "request_key04 cve-2017-17807" fixed
	# Bug 1578750 - ovl: hash directory inodes for fsnotify
	osver_in_range "700" "707" && tskip "inotify07" fixed
	# Bug 1578751 - ovl: hash non-dir by lower inode for fsnotify
	osver_in_range "700" "707" && tskip "inotify08" fixed
	# Bug 1645586 - execveat03 fails, missing upstream patch
	kernel_in_range "0" "4.14.0-116.el7a" && tskip "execveat03" fixed
	# Bug 1632639 - fanotify09 fails
	kernel_in_range "0" "4.14.0-116.el7a" && tskip "fanotify09" fixed
	# Bug 1632639 - bind03 fails
	kernel_in_range "0" "4.14.0-115.el7a"  && tskip "bind03" fixed
	# Bug 1596532 - VFS: regression in fsnotify, resulting in kernel panic or softlockup [7.6-alt]
	kernel_in_range "0" "4.14.0-113.el7a"  && tskip "inotify09" fixed
	# Bug 1760639 rhel7 timer_create: alarmtimer return wrong errno, on RTC-less system, s390x, ppc64
	osver_in_range "700" "707" && tskip "timer_delete01 timer_settime01 timer_settime02" fixed
}

function rhel_alt_knownissue_filter()
{
	rhel_alt_fatal_issues;
	rhel_alt_unfix_issues;
	rhel_alt_fixed_issues;
}
