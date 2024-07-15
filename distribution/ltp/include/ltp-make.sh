#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#TEST_VERSION can override the default
TESTVERSION=$TEST_VERSION
if [ -z ${TESTVERSION} ]; then
    if rlIsRHEL 6; then
        TESTVERSION="20200120"
    elif rlIsRHEL 7; then
        # NOTE: don't forget to update ltp version on dci/rhel7.xml as well
        TESTVERSION="20210927"
    elif rlIsRHEL 8 && rlIsRHEL '<=8.2'; then
        # NOTE: rhel82z build failed on newer ltp, fix to 20230929
        TESTVERSION="20230929"
    elif rlIsRHEL 8 || rlIsRHEL '<=9.4'; then
        # NOTE: don't forget to update ltp version on dci/rhel8.xml as well
        TESTVERSION="20240129"
    else
        TESTVERSION="20240524"
    fi
fi

# the task path may be different under the restraint harness if the task
# is fetched directly from git, so use a relative path to the include task
ABS_DIR=$(dirname ${BASH_SOURCE[0]})"/patches"
echo "Absolute directory of ltp include patches: $ABS_DIR"  | tee -a $OUTPUTFILE

TARGET_DIR="/mnt/testarea/ltp"
TARGET="ltp-full-${TESTVERSION}"

SYSENV=$(uname -m)
ARCH=$SYSENV
KVER=$(uname -r | cut -d'-' -f 1)
KREV=$(uname -r | cut -d'-' -f 2 | cut -d'.' -f 1)
KREV2=$(uname -r | cut -d'-' -f 2 | cut -d'.' -f 2)

# Whether NXBIT is Set in /proc/cpuinfo
NXBIT=$(grep '^flags' /proc/cpuinfo 2>/dev/null | grep -q " nx " && echo TRUE || echo FALSE)
NR_CPUS=$(getconf _NPROCESSORS_ONLN || echo 1)

MAKE="make -j${NR_CPUS}"

download_ltp()
{
    echo "============ Download package ============" | tee -a $OUTPUTFILE
    if [ -z "$LTP_DOWNLOAD_URL" ]; then
        curl --fail --retry 5 -s -SLO https://github.com/linux-test-project/ltp/releases/download/${TESTVERSION}/ltp-full-${TESTVERSION}.tar.bz2
        if [ $? -ne 0 ]; then
            TARGET=ltp-$TESTVERSION
            curl --fail --retry 5 -s -SLO https://gitlab.com/redhat/centos-stream/tests/ltp/-/archive/$TESTVERSION/ltp-$TESTVERSION.tar.bz2
        fi
    elif echo $LTP_DOWNLOAD_URL | grep -E "tar.bz2"; then
        LTP_DOWNLOAD_URL=${LTP_DOWNLOAD_URL//TESTVERSION/"$TESTVERSION"}
        TARGET=$(basename $(echo $LTP_DOWNLOAD_URL | sed 's/\.tar\.bz2//'))
        curl --fail --retry 5 -s -SLO $LTP_DOWNLOAD_URL
    else
        TARGET=ltp-${TESTVERSION}
        curl --fail --retry 5 -s -SLO ${LTP_DOWNLOAD_URL}/${TESTVERSION}/ltp-${TESTVERSION}.tar.bz2
    fi
    if [ $? -ne 0 ]; then
        echo "upstream download failed, giving up" | tee -a $OUTPUTFILE
        echo "Aborting current task: Couldn't download LTP source." | tee -a $OUTPUTFILE
        rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
        rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
    fi

    rm -rf ${TARGET}

    echo "============ Unzip package ============" | tee -a $OUTPUTFILE
    tar xjf ${TARGET}.tar.bz2 | tee -a $OUTPUTFILE
}

clone_ltp()
{
    TARGET=${PWD}/ltp
    rm -rf ${TARGET}
    git clone https://github.com/linux-test-project/ltp ${TARGET}
    if [ $? -ne 0 ]; then
        echo "Aborting current task: Couldn't clone LTP" | tee -a $OUTPUTFILE
        rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
        rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
    fi
    if [[ -n ${LTP_COMMIT_ID} && ${LTP_COMMIT_ID} != "latest" ]]; then
        git -C ${TARGET} checkout ${LTP_COMMIT_ID}
        if [ $? -ne 0 ]; then
            echo "Aborting current task: Couldn't checkout ${LTP_COMMIT_ID}" | tee -a $OUTPUTFILE
            rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
            rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
        fi
    fi
    if [[ -z ${LTP_COMMIT_ID} || ${LTP_COMMIT_ID} == "latest" ]]; then
        LTP_COMMIT_ID=$(git -C ${TARGET} log --format="%H" -n 1)
    fi
    TESTVERSION="commit-${LTP_COMMIT_ID}"

}

patch-generic()
{
    echo "============ General Patch ============" | tee -a $OUTPUTFILE
    echo " === applying general upstream fixes. ===" | tee -a $OUTPUTFILE
    echo " === applying general internal fixes. ===" | tee -a $OUTPUTFILE

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
    fi
    if [ "$TESTVERSION" == "20240129" ]; then
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-fix-broken-failure-detection-with-dmesg.patch
        # Tips: this patch should be applied in single on ltp-next(version > 20180926)
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore-new.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel9-support-futex_waitv.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-madvise06-set-max_runtime-to-60.patch
    fi
    if [ "$TESTVERSION" == "20230929" ]; then
        # Tips: this patch should be applied in single on ltp-next(version > 20180926)
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel9-support-futex_waitv.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-process_madvise01-fix-smaps-scan-and-min_sw.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-tools-Fix-syntax-error-caused-by-in-create_dmesg_ent.patch
        # Should be placed after 0001-tools-Fix-syntax-error-caused-by-in-create_dmesg_ent.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-fix-broken-failure-detection-with-dmesg.patch
    fi
    if [ "$TESTVERSION" == "20230516" ]; then
        # Tips: this patch should be applied in single on ltp-next(version > 20180926)
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel9-support-futex_waitv.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-tst_fill_fs-drop-safe_macro-from-fill_flat_vec.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-readahead02-set-dynamic-run-time.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-preadv203-guarantee-the-subloop-exit-timely.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-io_uring-enable-I-O-Uring-before-testing.patch
    fi
    if [ "$TESTVERSION" == "20230127" ]; then
        # Tips: this patch should be applied in single on ltp-next(version > 20180926)
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel9-support-futex_waitv.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-aiocp-remove-the-check-read-unnecessary-flag.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-dirtyc0w_shmem_child-64k-pagesize.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-mount03-flip-to-the-next-second-before-doing-the-acc.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-madvise06-stop-throwing-failure-when-MADV_WILLNEED-i.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-setfsuid02_16-Fix-uid-1-too-large-for-testing-16-bit.patch
    fi
    if [ "$TESTVERSION" == "20220930" ]; then
        # Tips: this patch should be applied in single on ltp-next(version > 20180926)
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel9-support-futex_waitv.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-cpuid.h-Provide-the-macro-definition-__cpuid_count.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-futex_waitv0-23-replace-TST_THREAD_STATE_WA.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-ptrace07-fix-the-broken-case-caused-by-hardcoded-xst.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-ptrace07-Fix-compilation-when-cpuid.h-is-missing.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-ptrace07-Fix-compilation-when-not-on-x86.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-ptrace07-Fix-compilation-by-avoiding-aligned_alloc.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-Revert-ptrace07-Fix-compilation-when-not-on-x86.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-cpuid-ptrace07-Only-compile-on-x86_64.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-kconfig-adding-new-config-path.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-keyctl02-make-use-of-.max_runtime.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-lib-introduce-safe_write-retry.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-update-all-call-sites-of-SAFE_WRITE.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-statx01-Fix-reading-64-bit-mnt_id-value-fro.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-statx01-Add-exit-condition-when-parsing-pro.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-statx01-Fix-typo.patch
    fi

    if [ "$TESTVERSION" == "20220527" ]; then
        # Tips: this patch should be applied in single on ltp-next(version > 20180926)
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel9-support-futex_waitv.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-lib-extend-.request_hugepages-to-guarantee-enough-hp.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-memfd_create03-make-use-of-new-.hugepages.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-pkey01-print-more-info-when-write-buff-fail.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-utime03-print-more-details-when-test-fails.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-madvise06-shrink-to-3-MADV_WILLNEED-pages-to-stabili.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-swapping01-make-use-of-remaining-runtime-in-test-loo.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/migrate_pages03_timeout.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-futex_waitv03-replace-TST_THREAD_STATE_WAIT.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-read_all-Add-worker-timeout-and-rewrite-scheduling.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0002-read_all-Fix-type-warnings.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0003-read_all-Allow-sys-power-wakeup_count.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0004-read_all-Prevent-FNM_EXTMATCH-redefinition.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-accept4_01-don-t-hardcode-port-number-for-t.patch
    fi

    if [ "$TESTVERSION" == "20220121" ]; then
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-clock_gettime04-set-threshold-based-on-the-clock-res.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-pread02-extend-buffer-to-avoid-glibc-overfl.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-fsync02-multiply-the-timediff-if-test-in-VM.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-clock_gettime03-multiply-the-timediff-if-test-in-VM.patch
    fi

    if [ "$TESTVERSION" == "20210927" ]; then
        # Tips: this patch should be applied in single on ltp-next(version > 20180926)
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel_only-migrate_page02-avoid-warning.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-tools-Fix-syntax-error-caused-by-in-create_dmesg_ent.patch
        # Should be placed after 0001-tools-Fix-syntax-error-caused-by-in-create_dmesg_ent.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-fix-broken-failure-detection-with-dmesg.patch
    fi

    if [ "$TESTVERSION" == "20200120" ]; then
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-tools-Fix-syntax-error-caused-by-in-create_dmesg_ent.patch
        # Should be placed after 0001-tools-Fix-syntax-error-caused-by-in-create_dmesg_ent.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-fix-broken-failure-detection-with-dmesg.patch
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
}

patch-lite()
{
    path_name=${PWD}
    cur_dir=$(echo ${path_name##*/})
    if [ "$cur_dir" != "lite" ]; then
        return
    fi

    echo "============ Patch ltp-lite ============" | tee -a $OUTPUTFILE
    cki_is_baremetal
    #Patching, if non-baremetal
    if [ $? -ne 0 ]; then
        if [[ "$TESTVERSION" == "20200120" || "$TESTVERSION" == "20210927" ]]; then
            sed -i 's/LL//' ${PATCHDIR}/ltp-include-relax-timer-thresholds-for-non-baremetal.patch
        fi
        patch -d ${TARGET} -p1 < ${PATCHDIR}/ltp-include-relax-timer-thresholds-for-non-baremetal.patch
    fi
}

patch-cgroups()
{
    echo "============ Applying ltp-cgroups patches. ============" | tee -a $OUTPUTFILE
    ${PATCH} < ${ABS_DIR}/INTERNAL/cgroup-debug-check-cgroups.patch
}


patch-inc()
{
    patch-generic
    patch-lite
}


# Setup desired filesystem mounted at /mnt/testarea
# TEST_DEV or TEST_MNT can be set, this useful when testing filesystems in beaker
#
# If TEST_DEV is set, mkfs on TEST_DEV and mount it at /mnt/testarea
# If TEST_MNT is set, grab device mounted at TEST_MNT first and mkfs & mount at
# /mnt/testarea
#
# Also MKFS_OPTS and MOUNT_OPTS can be set to specify mkfs and mount options, e.g.
# FSTYP=xfs MKFS_OPTS="-m crc=1" MOUNT_OPTS="-o relatime"  bash ./runtest
setup-testarea()
{
    if [ "${TEST_DEV}" != "" ] || [ "${TEST_MNT}" != "" ]; then
        echo "============ Setup /mnt/testarea ============"
        if [ "${FSTYP}" == "" ]; then
            echo " - Having TEST_DEV or TEST_MNT set but not FSTYP" | tee -a $OUTPUTFILE
            exit 1
        fi
        if [ "${TEST_MNT}" != "" ]; then
            dev=`grep "${TEST_MNT}" /proc/mounts | awk '{print $1}'`
            if [ -z $dev ]; then
                echo " - TEST_MNT set to ${TEST_MNT}, but no partition mounted there" | tee -a $OUTPUTFILE
                exit 1
            fi
            cp /etc/fstab{,.bak}
            grep -v ${TEST_MNT} /etc/fstab.bak >/etc/fstab
            umount ${TEST_MNT}
        fi
        if [ "$dev" == "" ] && [ "${TEST_DEV}" != "" ]; then
            dev=$(TEST_DEV)
        fi
        if [ "$dev" == "" ]; then
            echo " - No suitable test device found" | tee -a $OUTPUTFILE
            exit 1
        fi
        if [ "${FSTYP}" == "xfs" ] || [ "${FSTYP}" == "btrfs" ]; then
            mkfs -t ${FSTYP} ${MKFS_OPTS} -f $dev
        elif [ "${FSTYP}" == "overlayfs" ]; then
            mkfs -t xfs -n ftype=1 -f $dev
        else
            mkfs -t ${FSTYP} ${MKFS_OPTS} $dev
        fi
        if [ $? -ne 0 ]; then
            echo " - mkfs failed" | tee -a $OUTPUTFILE
            exit 1
        fi
        if [ "$FSTYP" == "overlayfs" ]; then
            mkdir -p /mnt/ltp-overlay
            mount ${MOUNT_OPTS} $dev /mnt/ltp-overlay
            mkdir -p /mnt/ltp-overlay/lower
            mkdir -p /mnt/ltp-overlay/upper
            mkdir -p /mnt/ltp-overlay/workdir
            mount -t overlay overlay -olowerdir=/mnt/ltp-overlay/lower,upperdir=/mnt/ltp-overlay/upper,workdir=/mnt/ltp-overlay/workdir /mnt/testarea
        else
            mount ${MOUNT_OPTS} $dev /mnt/testarea
        fi
        if [ $? -ne 0 ]; then
            echo " - mount $dev at /mnt/testarea failed" | tee -a $OUTPUTFILE
            exit 1
        fi
    fi
}

configure()
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

    #Patch-inc
    echo "============ Patch patch-inc-tolerant ==============" | tee -a $OUTPUTFILE
    patch-inc > patchinc.log 2>&1
    cat patchinc.log | tee -a $OUTPUTFILE

    echo "============ Start configure ============" | tee -a $OUTPUTFILE
    AUTOCONFIGVER=$(rpm -qa autoconf |cut -f 2 -d "-")
    # AUTOMAKEVER=$(rpm -qa automake |cut -f 2 -d "-"|cut -f 1,2 -d ".")
    AUTOCONFIGVER_1=$(echo $AUTOCONFIGVER |cut -f 1 -d ".")
    AUTOCONFIGVER_2=$(echo $AUTOCONFIGVER |cut -f 2 -d ".")
    DOWNLOAD_URL=$(echo ${LOOKASIDE:-http:\/\/download.devel.redhat.com\/qa\/rhts\/lookaside\/})
    if [[ $AUTOCONFIGVER_1 -lt 1 || $AUTOCONFIGVER_1 -eq 2 && $AUTOCONFIGVER_2 -lt 69 ]]; then \
        wget -q $DOWNLOAD_URL/m4-1.4.16.tar.gz ; \
        tar xzf m4-1.4.16.tar.gz; \
        pushd  m4-1.4.16; \
        ./configure --prefix=/usr > /dev/null 2>&1; \
        make > /dev/null 2>&1 && make install > /dev/null 2>&1; \
        popd ; \
        wget -q $DOWNLOAD_URL/autoconf-2.69.tar.gz ; \
        tar xzf autoconf-2.69.tar.gz; \
        pushd autoconf-2.69; \
        ./configure --prefix=/usr > /dev/null 2>&1 ; \
        make > /dev/null 2>&1 && make install > /dev/null 2>&1; \
        popd ; \
    fi
    pushd ${TARGET}; make autotools; ./configure --prefix=${TARGET_DIR} &> configlog.txt || cat configlog.txt; popd
}

build-all()
{
    setup-testarea
    if [[ -z ${LTP_COMMIT_ID} ]]; then
        download_ltp
    else
        clone_ltp
        if [[ -f ${TARGET_DIR}/runltp ]] && grep -q "${TESTVERSION}" ${TARGET_DIR}/ltp_version; then
            # the LTP_COMMIT_ID is already the version installed
            return
        fi
        # generate RHELKT1LITE.next
        echo "Going to generate RHELKT1LITE.next"
        pushd ../lite/configs
        # restraint doesn't seem to keep the file permission
        chmod +x ./config-maker.sh
        LTP_VERSION=next ./config-maker.sh &> config-maker.txt
        if [ $? -ne 0 ]; then
            cat config-maker.txt
            echo "Aborting current task: Couldn't generate test config." | tee -a $OUTPUTFILE
            rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
            rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
        fi
        popd
        echo "RHELKT1LITE.next is generated"
    fi
    configure
    echo "============ Start ${MAKE} and install ============" | tee -a $OUTPUTFILE
    timeout_value=30
    if uname -r | grep -q '+debug'; then
        timeout_value=90
    fi
    res="PASSED"
    timeout "${timeout_value}m" ${MAKE} -C ${TARGET} all &> buildlog.txt
    build_res=$?
    if [ ${build_res} -eq 124 ]; then
        echo "Cleaning up ${TARGET_DIR}"
        rm -rf ${TARGET_DIR}
        rstrnt-report-result "build-all build timeout" WARN/ABORTED
        rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
        exit 1
    fi
    if [ ${build_res} -ne 0 ]; then
        res="FAILED"
        SubmitLog ./buildlog.txt
        rstrnt-report-result "build-all build failed" WARN/ABORTED
        rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
        exit 1
    fi
    echo "============ ${MAKE} -C ${TARGET} all: ${res}  ============" | tee -a $OUTPUTFILE
    res="PASSED"
    ${MAKE} -C ${TARGET} install &> buildlog.txt
    if [ $? -ne 0 ]; then
        res="FAILED"
    fi
    echo "============ ${MAKE} -C ${TARGET} install: ${res}  ============" | tee -a $OUTPUTFILE
    SubmitLog ./buildlog.txt
    if [[ ${res} == "PASSED" ]]; then
        echo "${TESTVERSION}" > ${TARGET_DIR}/ltp_version
    else
        if [[ -n $RSTRNT_TASKID ]]; then
            rstrnt-report-result "build-all failed" WARN/ABORTED
            rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
        else
            exit 1
        fi
    fi
}

# For manual testing
testpatch()
{
    download_ltp
    patch-inc
}

testconfigure()
{
    download_ltp
    patch-inc
    configure
}

testfullbuild()
{
    build-all
}
