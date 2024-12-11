#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include beaker environment
. ../../../cki_lib/libcki.sh || exit 1
. ../../../kernel-include/runtest.sh || exit 1

# Logic:
# 1. Download the SRPM and install the SRPM
# 2. Find the source tarball and decompress
# 3. Extract the lib/test_bpf.c
# 4. obj-m+= test_bpf.o in Makefile
# 5. make -C /lib/modules/`uname -r`/build M=`pwd` modules
# 6. insmod test_bpf.ko
# 7. journalctl -k --full | sed "s/$(hostname)//g"
# Expected result
# Apr 25 04:30:10  kernel: test_bpf: Summary: 349 PASSED, 0 FAILED, [0/341 JIT'ed]

yum=$(cki_get_yum_tool)

rlJournalStart
    rlPhaseStartSetup
        # soft dependency, don't fail in case a package can't be installed
        for i in libgcc glibc-static gcc gcc-c++ kernel-devel elfutils-libelf-devel binutils-devel libcap-devel openssl-devel python3; do
            $yum install -y $i
        done
        # nfs-utils git util-linux createrepo genisoimage gcc gcc-c++ rpm-build kernel-abi-whitelists wget python-setuptools
        # yum install -y elfutils-libelf-devel binutils-devel newt-devel python-devel perl xmlto asciidoc perl-ExtUtils-Embed
        devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)
        $yum install -y "${devel_pkg}" || $yum download "${devel_pkg}" || rlRpmDownload "${devel_pkg}"
        kernel_rpm_name=$(K_GetRunningKernelRpmName)
        running_kernel=$(K_GetRunningKernelRpmVersionRelease)
        $yum download "${kernel_rpm_name}"-"${running_kernel}" --source || rlRpmDownload --source "${kernel_rpm_name}"-"${running_kernel}"

        rpm -q "${devel_pkg}" || rpm -ivh --force "${devel_pkg}".rpm
        rpm -ivh --force $(rpm -q --queryformat '%{sourcerpm}\n' -qf /boot/config-$(uname -r))

        $yum install -y kmod

        tar Jxf ~/rpmbuild/SOURCES/linux-"${running_kernel}"*.tar.xz
        ksrcdir=`find . -maxdepth 1 -name linux-"${running_kernel}"`
        rm -rf test_bpf
        mkdir test_bpf
        find . -name test_bpf.c -exec cp {} test_bpf \;
        echo 'obj-m+= test_bpf.o' > test_bpf/Makefile
        pushd "${ksrcdir}"
            cp /boot/config-$(uname -r) .config
            make oldconfig
            make prepare
            make modules_prepare
        popd
        pushd test_bpf
        BEAHARCH=${ARCH}
        unset ARCH
        if [ -f /boot/symvers-"${running_kernel}".$(arch).xz ]; then
            xzcat /boot/symvers-"${running_kernel}".$(arch).xz > ../"${ksrcdir}"/Module.symvers
        elif [ -f /boot/symvers-"${running_kernel}".$(arch).gz ]; then
            gunzip -c /boot/symvers-"${running_kernel}".$(arch).gz > ../"${ksrcdir}"/Module.symvers
        fi

        make -C ../"${ksrcdir}"/ M=`pwd` modules
        popd
        rmmod test_bpf
        ARCH=${BEAHARCH}
    rlPhaseEnd
    rlPhaseStartTest "Loading test_bpf"
        rlRun "insmod test_bpf/test_bpf.ko"
        sleep 5
        journalctl -k --full | sed "s/$(hostname)//g" &> insmod_test_bpf.log
        rlFileSubmit insmod_test_bpf.log
        rlRun "cat insmod_test_bpf.log | egrep -v 'Summary|signature' | grep -i test_bpf | grep -i failed" 1 "Should not find any failure"
        rmmod test_bpf
    rlPhaseEnd
rlJournalEnd
