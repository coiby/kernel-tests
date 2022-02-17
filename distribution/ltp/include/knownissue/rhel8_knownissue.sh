#!/bin/bash

function rhel8_fatal_issues()
{
	if [ "$(find /sys/firmware/efi/vars -name raw_var | wc -l)" -ge 1 ];
	then
		# Bug 1628542: kernel panic running LTP read_all_sys on UEFI systems
		osver_in_range "800" "803" && tskip "read_all_sys" fatal
	fi
	# Bug 1684734 - [RHEL-8.0][s390x]ltp-lite mtest06 testing hits EWD due to
	osver_in_range "800" "802" && is_arch "s390x" && tskip "mtest06" fatal
	# Bug 1738338 - [ RHEL-8.1][PANIC][kernel-debug] Oops: 0000 [#1] SMP KASAN NOPTI
	osver_in_range "800" "803" && tskip "proc01" fatal
}

function rhel8_unfix_issues()
{
	# Bug 1945052 - CVE-2021-3444 kernel: bpf verifier incorrect mod32 truncation
	osver_in_range "800" "806" && tskip "bpf_prog05 cve-2021-3444" unfix
	# Bug 1879689 - [RHEL-8.3] move_pages12.c:95: FAIL: madvise failed: ENOMEM (12)
	osver_in_range "800" "805" && is_arch "aarch64" && tskip "move_pages12" unfix
	# Bug 1880265 - RHEL8.3 Snapshot1 - Slab memory controller issue (mm-)
	osver_in_range "800" "805" && tskip "madvise06" unfix
	# Bug 1832099 - fanotify: fix merging marks masks with FAN_ONDIR
	osver_in_range "800" "806" && tskip "fanotify09" unfix
	# Bug 1805587 - [FJ8.2 Bug]: system crash happened due to NULL pointer dereference at slip_write_wakeup()
	osver_in_range "800" "804" && tskip "pty03" unfix
	# Bug 1657032 - fallocate05 intermittently failing in ltp lite
	osver_in_range "800" "801" && tskip "fallocate05" unfix
	# Bug 1660161 - [RHEL8] ltp/generic commands mkswap01 fails to create by-UUID device node in aarch64
	osver_in_range "800" "801" && is_arch "aarch64" && tskip "mkswap01" unfix
	# Bug 1650597 - [RHEL8][aarch64][Huawei] ltp/lite migrate_pages failures in T2280
	osver_in_range "800" "801" && is_arch "aarch64" && tskip "migrate_pages03" unfix
	# Bug 1724724 - [RHEL-8.1]LTP: SMSW operation get success with KVM UMIP enabled from userspace
	is_kvm && is_arch "x86_64" && tskip "umip_basic_test" unfix
        # Bug 1739587 - [RHEL-8.1] ltp/generic: syscalls/perf_event_open02 test failures on RT kernel
        is_rt && osver_in_range "800" "802" && tskip "perf_event_open02" unfix
	# Bug 1758717 - Snap 4.1 LTP move_pages fail
	osver_in_range "800" "803" && tskip "move_pages12" unfix
	# Bug 1777554 - false positive with huge pages on aarch64
	# Note: this can be removed when pkey01 is fixed upstream
	#       http://lists.linux.it/pipermail/ltp/2019-December/014683.html
	is_arch "aarch64" && tskip "pkey01" unfix
	# Bug 1789964 [RHEL-8.2][aarch64/ppc64le] ltp/lite fork09 - fails to complete
	pkg_in_range "systemd" "239-20" "239-25" && tskip "fork09" unfix
	# s390x failed cases.
	is_arch "s390x" && tskip "open04 create05" unfix
	# Bug 1804478 scheduler exceeds prctl timerslack on s390x
	osver_in_range "800" "805" && is_arch "s390x" && tskip "prctl09" unfix
	# Bug 1842025 - ltp: connect02: setsockopt(IPV6_ADDRFORM) failed: ENOPROTOOPT (92)
	tskip "connect02" unfix
	# Bug 1842076 - ltp: ptrace09 PANIC: double fault, error_code: 0x0
	tskip "ptrace09" unfix
	# Failing on s390x, ppc64le
	(is_arch "s390x" || is_arch "ppc64le") && tskip "ioctl_loop05" unfix
	# Bug 1842628 - [RHEL-8.3][ltp-lite] pty04.c:264: FAIL: Padding bytes may contain stack data b1 ff ff
	tskip "pty04 cve-2020-11494" unfix
	# Bug 1844854 - ltp: bpf_prog01 Failed verification: in-kernel BTF is malformed
	is_arch "s390x" && tskip "bpf_prog01" unfix
	# Bug 1845879 - fanotify: fix ignore mask logic for events on child and on dir
	osver_in_range "800" "806" && tskip "fanotify10" unfix
	# ptrace08 case issue, tst_kvercmp isn't suitable for rhel8's kernel version
	osver_in_range "800" "805" && tskip "ptrace08 cve-2018-1000199" unfix
	# Unable to load BPF programs on s390x kernels built by CKI
	# https://projects.engineering.redhat.com/browse/FASTMOVING-1825
	is_arch "s390x" && tskip "bpf_prog01 bpf_prog02" unfix
	# Bug 1981743 - RHEL-9-Beta: WARNING: CPU: 3 PID: 0 at kernel/sched/fair.c:401 enqueue_task_fair+0x254/0x5b0
	osver_in_range "800" "806" && tskip "cfs_bandwidth01" unfix
}

function rhel8_fixed_issues()
{
	# Bug 1895961 (CVE-2020-25704) - CVE-2020-25704 kernel: perf_event_parse_addr_filter memory
	kernel_in_range "0" "4.18.0-193.59.1.el8" && tskip "perf_event_open03" fixed
	# Bug 1913045 - [RHEL-8.4.0] ltp/lite - ioctl_sg01 - fail - broken mmap() for MAP_FAILED
	is_arch "aarch64" && kernel_in_range "0" "kernel-4.18.0-304.5.el8" && tskip "ioctl_sg01" unfix
	# Bug 1820405 - KEYS: allow reaching the keys quotas exactly
	kernel_in_range "0" "4.18.0-193.7.el8" && tskip "add_key05" fixed
	# Bug 1771351 - fat: race between udev and mkdir leads to EIO
	kernel_in_range "0" "4.18.0-194.el8" && tskip "statx04" fixed
	# Bug 1760638  timer_create: alarmtimer return wrong errno, on RTC-less system, s390x, ppc64
	kernel_in_range "0" "4.18.0-148.el8" && tskip "timer_delete01 timer_settime01 timer_settime02" fixed
	! is_arch "x86_64" && osver_in_range "800" "803" && tskip "timer_create01" fixed
	# Bug 1734286 - mm: mempolicy: make mbind() return -EIO when MPOL_MF_STRICT is specified
	kernel_in_range "0" "4.18.0-148.el8" && tskip "mbind02" fixed
	# Bug 1718370 - overlayfs fixes up to upstream 5.2
	kernel_in_range "0" "4.18.0-109.el8" && tskip "fanotify06" fixed
	# Bug 1657880 - CVE-2018-19854 kernel: Information Disclosure in crypto_report_one in crypto/crypto_user.c
	kernel_in_range "0" "4.18.0-80.13.el8" && tskip "cve-2018-19854 crypto_user01" fixed
	# Bug 1638647 - ltp execveat03 failed, as missing "355139a8dba4
	kernel_in_range "0" "4.18.0-27.el8" && tskip "execveat03" fixed
	# Bug 1652432 - fanotify: fix handling of events on child sub-directory
	kernel_in_range "0" "4.18.0-50.el8" && tskip "fanotify09" fixed
	# 20200515 updated fallocate06 xfs failure disappeared since kernel-4.18.0-194.el8
	kernel_in_range "0" "4.18.0-194.el8" && tskip "fallocate06" fixed
	# Bug 1820405 - KEYS: allow reaching the keys quotas exactly        fixed 4.18.0-193.7.el8 during early dev
	kernel_in_range "0" "4.18.0-194.el8" && tskip "add_key05" fixed
	# Bug 1875699 - CVE-2020-14386 kernel: memory corruption in net/packet/af_packet.c leads to elevation of privilege
	kernel_in_range "0" "4.18.0-237.el8" && tskip "sendto03 cve-2020-14386" fixed
	# Bug 1985920 - [RHEL-8.2] LTP quotactl07 failed : Q_XQUOTARM doesn't have quota type check
	kernel_in_range "0" "4.18.0-195.el8" && tskip "quotactl07" fixed
	pkg_in_range "glibc" "0" "2.28-153.el8" && tskip "semctl09" fixed
	# Bug 2004810 - [FJ8.5 Bug]: LTP creat09, which is a test for CVE-2018-13405, failed.
	kernel_in_range "0" "4.18.0-349.el8" && tskip "creat09 cve-2018-13405" fixed
}

function rhel8_knownissue_filter()
{
	rhel8_fatal_issues;
	rhel8_unfix_issues;
	rhel8_fixed_issues;
	if is_zstream; then
		# Bug 1875699 - CVE-2020-14386 kernel: memory corruption in net/packet/af_packet.c leads to elevation of privilege
		kernel_in_range "4.18.0-147.31.1.el8_1" "4.18.0-147.9999"  && tback "sendto03 cve-2020-14386"
		# Bug 1875699 - CVE-2020-14386 kernel: memory corruption in net/packet/af_packet.c leads to elevation of privilege
		kernel_in_range "4.18.0-193.23.1.el8_2" "4.18.0-193.9999"  && tback "sendto03 cve-2020-14386"
	fi
}
