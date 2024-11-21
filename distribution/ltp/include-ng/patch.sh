#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#

patch_generic()
{
	echo "============ Applying General Patch ============" | tee -a $OUTPUTFILE

	if [ "$TESTVERSION" == "20240930" ]; then
		# Tips: this patch should be applied in single on ltp-next(version > 20180926)
		${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
		${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore-new.patch
		${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel9-support-futex_waitv.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-Filter-mkfs-version-in-tst_fs.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-Add-minimum-kernel-requirement-for-FS-setup.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-lib-tst_test.c-fix-NULL-ptr-deref-when-filesystems-i.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-move_pages04-check-for-invalid-area-no-page-mapped-a.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-move_pages04-remove-special-casing-for-kernels-4.3.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-move_pages04-convert-to-new-test-API.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-read_all-limit-sysfs-tpm-entries-to-single-worker.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-Fallback-landlock-network-support.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0002-Network-helpers-in-landlock-suite-common-functions.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0003-Add-landlock08-test.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0004-Add-error-coverage-for-landlock-network-support.patch
	fi

	if [ "$TESTVERSION" == "20240524" ]; then
		# Tips: this patch should be applied in single on ltp-next(version > 20180926)
		${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
		${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore-new.patch
		${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel9-support-futex_waitv.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-configure.ac-Add-_GNU_SOURCE-for-struct-fs_quota_sta.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0002-quotactl07-add-_GNU_SOURCE-define.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0003-rpc_svc_1-Fix-incompatible-pointer-type-error.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-libswap-Fix-tst_max_swapfiles-for-c9s-latest.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-tst_kconfig-Avoid-reporting-buffer-overflow-when-par.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-msgstress01-remove-TWARN-from-runtime-remaining.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-realtime-prio-preempt-take-cpu-isolation-into-consid.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-kallsyms-skip-user-space-mapped-addresses.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-perf_event_open-improve-the-memory-leak-detection.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-Add-cachestat-fallback-definitions.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0002-Add-cachestat01-test.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0003-Add-cachestat02-test.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0004-Add-cachestat03-test.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0006-Add-cachestat04-test.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-cachestat-remove-.min_kver-from-cachestat-tests.patch
		${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-cachestat01-Reduce-required-space-on-64kb-page-size.patch
	fi

	if [ "$ARCH" == "ppc" ] || [ "$ARCH" == "ppc64" ] || [ "$ARCH" == "s390" ] || [ "$ARCH" == "s390x" ]; then
		echo " - remove kernel/firmware tests in s390/ppc64 arch" | tee -a $OUTPUTFILE
		${PATCH} < ${ABS_DIR}/INTERNAL/skip-firmware-tests.patch
	fi

	if  [[ $TESTVERSION =~ ^[0-9]+$ ]] && [[ $TESTVERSION -ge 20170516 ]]; then
		echo " - cron_tests.sh has been rewritten since ltp-20170516" | tee -a $OUTPUTFILE
	fi

	if [ "$NXBIT" == "TRUE" ]; then
		echo " - fix crashme testcase on systems with NX flag." | tee -a $OUTPUTFILE
		${PATCH} < ${ABS_DIR}/INTERNAL/rhel-scrashme-remove-f00f-test-on-system-with-NX-bit.patch
	fi

	if [ "$ARCH" == "aarch64" ]; then
		echo " - no aarch64 patches needed at this time" | tee -a $OUTPUTFILE
	fi

	if [ "$KVER" == "5.14.0" ] && ([ "$KREV" = "284" ] && [ "$KREV2" -ge "33" ] || [ "$KREV" -ge "362" ]); then
		echo " - returning ENODEV for empty cpumask stands for reseting user cpu mask" | tee -a $OUTPUTFILE
		${PATCH} < ${ABS_DIR}/INTERNAL/sched_setaffinity_ENODEV.patch
	fi

	if [[ $KVER =~ ^6 ]]; then
		${PATCH} < ${ABS_DIR}/INTERNAL/build-cve-2015-3290.patch
	fi
}

patch_lite()
{
	path_name=${PWD}
	cur_dir=$(echo ${path_name##*/})
	if [ "$cur_dir" != "lite" ]; then
		return
	fi

	echo "============ Patch ltp-lite ============" | tee -a $OUTPUTFILE
	cki_is_baremetal
	if [ $? -ne 0 ]; then
		patch -d ${TARGET} -p1 < ${PATCHDIR}/ltp-include-relax-timer-thresholds-for-non-baremetal.patch
	fi
}

patch_cgroups()
{
	echo "============ Applying ltp-cgroups patches. ============" | tee -a $OUTPUTFILE
	${PATCH} < ${ABS_DIR}/INTERNAL/cgroup-debug-check-cgroups.patch
}

patch_inc()
{

	# if TEST_VERSION is set, use the --forward flag so patches which are
	# already applied do not cause the entire job to fail, and ignore
	# the exit status (which will be 1 for an error even with --forward)
	if [ ! -n "$TEST_VERSION" ]
	then
		PATCH="patch -p1 -d ${TARGET}"
	else
		PATCH="patch --forward -p1 -d ${TARGET}"
	fi
	patch_generic
	patch_lite
}

patch-rtltp()
{
    echo "============ Patch rt_ltp ============" | tee -a $OUTPUTFILE
    patch -d ${TARGET} -p1 < ${ABS_DIR}/${TESTVERSION}/0001-rhivos-increase-threshold-based-on-hardware.patch
    find ${TARGET} -type f -name run_auto.sh -exec chmod a+x {} \;  # Solve VROOM-23546
}
