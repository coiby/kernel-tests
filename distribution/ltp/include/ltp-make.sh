#!/bin/bash
#
#
#TEST_VERSION can override the default
TESTVERSION=${TEST_VERSION:-"20210121"}


# the task path may be different under the restraint harness if the task
# is fetched directly from git, so use a relative path to the include task
ABS_DIR=$(dirname ${BASH_SOURCE[0]})"/patches"
echo "Absolute directory of ltp include patches: $ABS_DIR"  | tee -a $OUTPUTFILE

TARGET_DIR="/mnt/testarea/ltp"
TARGET="ltp-full-${TESTVERSION}"

SYSENV=$(uname -i)
ARCH=$SYSENV
KVER=$(uname -r | cut -d'-' -f 1 | cut -d'.' -f 3)
KREV=$(uname -r | cut -d'-' -f 2 | cut -d'.' -f 1)
OS_MAJOR_RELEASE=$(grep -Go 'release [0-9]\+' /etc/redhat-release | sed 's/release //')

# Whether NXBIT is Set in /proc/cpuinfo
NXBIT=$(grep '^flags' /proc/cpuinfo 2>/dev/null | grep -q " nx " && echo TRUE || echo FALSE)
NR_CPUS=$(getconf _NPROCESSORS_ONLN || echo 1)
# Allow lab sites to use their local $LOOKASIDE domain
DOWNLOAD_URL=${LOOKASIDE:-"http://linux-test-project/ltp/releases/download/"}
IS_DEVEL=$(echo $DOWNLOAD_URL} | grep -o devel)
#global sync seems not working properly for now, use reverse proxy
#RELPATH=$(hostname | grep -v nay | grep -qv brq && echo / || echo /pub/rhel)
RELPATH="/"

MAKE="make -j${NR_CPUS}"
# if TEST_VERSION is set, use the --forward flag so patches which are
# already applied do not cause the entire job to fail, and ignore
# the exit status (which will be 1 for an error even with --forward)
if [ ! -n "$TEST_VERSION" ]
then
    PATCH="patch -p1 -d ${TARGET}"
else
    PATCH="-patch --forward -p1 -d ${TARGET}"
fi

download_ltp()
{
    echo "============ Download package ============" | tee -a $OUTPUTFILE
    wget -q ${DOWNLOAD_URL}/${TARGET}.tar.bz2
    if [ $? -ne 0 -a x${IS_DEVEL} = x ]; then
        echo "global sync seems not working correctly, using default location" | tee -a $OUTPUTFILE
        wget -q https://github.com/linux-test-project/ltp/releases/download/${TESTVERSION}/ltp-full-${TESTVERSION}.tar.bz2
        if [ $? -ne 0 ]; then
            echo "upstream download failed, giving up" | tee -a $OUTPUTFILE
        fi
    fi

    clean_ltp

    echo "============ Unzip package ============" | tee -a $OUTPUTFILE
    tar xjf ${TARGET}.tar.bz2 | tee -a $OUTPUTFILE
}


clean_ltp()
{
    rm -rf ${TARGET}
    rm -rf m4-1.4.16
    rm -rf autoconf-2.69
}


# Critical patches
# 1. If a patch fixes installation issue
# 2. a patch fixes critical issues (causing deadlock, crash, etc), no
#	matter the test will be executed or not, it should be applied here.
patch-critical()
{
    echo "============ Critical Patch ============" | tee -a $OUTPUTFILE
    ${PATCH} < ${ABS_DIR}/INTERNAL/rhel-scrashme-remove-fork12-test.patch
}


patch-generic()
{
    echo "============ General Patch ============" | tee -a $OUTPUTFILE
    echo " === applying general upstream fixes. ===" | tee -a $OUTPUTFILE
    echo " === applying general internal fixes. ===" | tee -a $OUTPUTFILE

    if [ "$TESTVERSION"  == "20200930" ]; then
        # Tips: this patch should be applied in single on ltp-next(version > 20180926)
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-rhel_only-migrate_page02-avoid-warning.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-shmat03-ignore-EACCES.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-btrfs-as-we-don-t-support-it-anymore.patch
        ${PATCH} < ${ABS_DIR}/INTERNAL/0001-Disable-zram-btrfs-support.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-crypto-af_alg07-Skip-this-case-when-not-having-sockf.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-send02-Ensure-recv-succeed-when-not-using-M.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-semop-Increase-timeout-for-semop03.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-lib-tst_cgroup-fix-short-reads-of-mems-cpus.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-madvise06-Increase-reliability-and-diagnostic-info.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-madvise06-Add-tag-for-mm-memcg-link-page-counters-to.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-madvise06-Allow-for-kmem-and-memsw-counters-being-di.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-syscalls-madvise06-Add-check-for-proc-sys-vm-stat_re.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-libnewipc-Add-get_ipc_timestamp.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0002-syscalls-ipc-Make-use-of-get_ipc_timestamp.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-lib-add-.min_cpus-in-tst_test-struct.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0002-syscalls-make-use-of-.min_cpus.patch
        ${PATCH} < ${ABS_DIR}/${TESTVERSION}/0001-af_alg07-add-dynamic-bias-for-ARM.patch
    fi

    # The following ones are for specific hardware/release
    if ([ "$OS_MAJOR_RELEASE" == "4" ] || [ "$OS_MAJOR_RELEASE" == "5" ]) && ([ "$ARCH" == "s390" ] || [ "$ARCH" == "s390x" ]); then
        echo " - remove cfs sched hacbench in RHEL[45] and s390x" | tee -a $OUTPUTFILE
        $(PATCH) < $(ABS_DIR)/INTERNAL/rhel345-sched-remove-cfs-sched-hackbench.patch
    fi

    if [ "$ARCH" == "ppc" ] || [ "$ARCH" == "ppc64" ] || [ "$ARCH" == "s390" ] || [ "$ARCH" == "s390x" ]; then
        echo " - remove kernel/firmware tests in s390/ppc64 arch" | tee -a $OUTPUTFILE
        ${PATCH} < ${ABS_DIR}/INTERNAL/skip-firmware-tests.patch
    fi

    if  [ $TESTVERSION  -ge 20170516 ]; then
        echo " - cron_tests.sh has been rewritten since ltp-20170516" | tee -a $OUTPUTFILE
    elif [  "$OS_MAJOR_RELEASE"  == "6" ]; then
        echo " - fix cron01 in RHEL6" | tee -a $OUTPUTFILE
        ${PATCH} < ${ABS_DIR}/INTERNAL/rhel6-commands-cron-ensure-syslog-enabled.patch
    fi

    if [ "$NXBIT" == "TRUE" ]; then
        echo " - fix crashme testcase on systems with NX flag." | tee -a $OUTPUTFILE
        ${PATCH} < ${ABS_DIR}/INTERNAL/rhel-scrashme-remove-f00f-test-on-system-with-NX-bit.patch
    fi

    if [ "$ARCH" == "aarch64" ]; then
        echo " - no aarch64 patches needed at this time" | tee -a $OUTPUTFILE
    fi
}


patch-cgroups()
{
    echo "============ Applying ltp-cgroups patches. ============" | tee -a $OUTPUTFILE
    ${PATCH} < ${ABS_DIR}/INTERNAL/cgroup-debug-check-cgroups.patch
}


patch-inc()
{
    patch-critical
    patch-generic
}


AUTOCONFIGVER=$(rpm -qa autoconf |cut -f 2 -d "-")
AUTOMAKEVER=$(rpm -qa automake |cut -f 2 -d "-"|cut -f 1,2 -d ".")
AUTOCONFIGVER_1=$(echo $AUTOCONFIGVER |cut -f 1 -d ".")
AUTOCONFIGVER_2=$(echo $AUTOCONFIGVER |cut -f 2 -d ".")

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
        if [ "${STYP}" == "overlayfs" ]; then
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
    setup-testarea
    download_ltp
    echo "============ Start configure ============" | tee -a $OUTPUTFILE
    if [ ${AUTOCONFIGVER_1} -lt 1 -o ${AUTOCONFIGVER_1} -eq 2 -a ${AUTOCONFIGVER_2} -lt 69 ]; then
        wget -q ${DOWNLOAD_URL}/m4-1.4.16.tar.gz
        tar xzf m4-1.4.16.tar.gz
        pushd  m4-1.4.16
        ./configure --prefix=/usr 2>&1 >/dev/null
        make 2>&1 >/dev/null && make install 2>&1 >/dev/null
        popd
        wget -q ${DOWNLOAD_URL}/autoconf-2.69.tar.gz
        tar xzf autoconf-2.69.tar.gz
        pushd autoconf-2.69
        ./configure --prefix=/usr 2>&1 >/dev/null
        make 2>&1 >/dev/null && make install 2>&1 >/dev/null
        popd
    fi
    pushd ${TARGET}; make autotools; ./configure --prefix=${TARGET_DIR} &> configlog.txt || cat configlog.txt; popd
}


build-basic()
{
    configure
    echo "============ Start make and install ============" | tee -a $OUTPUTFILE
    ${MAKE} -C ${TARGET}/pan all
    ${MAKE} -C ${TARGET}/pan install
    ${MAKE} -C ${TARGET}/runtest install
    ${MAKE} -C ${TARGET}/tools all
    ${MAKE} -C ${TARGET}/tools install
    ${MAKE} -C ${TARGET} Version
    cd ${TARGET}; cp -f ver_linux Version runltp IDcheck.sh ${TARGET_DIR}/
}


build-all()
{
    configure
    echo "============ Start ${MAKE} and install ============" | tee -a $OUTPUTFILE
    ${MAKE} -C ${TARGET} all &> buildlog.txt
    res="PASSED"
    if [ $? -ne 0 ]; then
        res="FAILED"
    fi
    echo "============ ${MAKE} -C ${TARGET} all: ${res}  ============" | tee -a $OUTPUTFILE
    res="PASSED"
    ${MAKE} -C ${TARGET} install &> buildlog.txt
    if [ $? -ne 0 ]; then
        res="FAILED"
    fi
    echo "============ ${MAKE} -C ${TARGET} install: ${res}  ============" | tee -a $OUTPUTFILE
}


clean()
{
    rm -rf ${TARGET}
    rm -rf m4-1.4.16
    rm -rf autoconf-2.69
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
    download_ltp
    patch-inc
    build-all
}
