#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/mce-test/include
#   Description: Common functions for mce-test tests
#   Author: Evan McNabb <emcnabb@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include rhts environment
. /usr/bin/rhts-environment.sh
. /usr/lib/beakerlib/beakerlib.sh

# Upstream URLs for future reference:
# git://github.com/andikleen/mce-test.git
# git://github.com/andikleen/mce-inject.git
# #git://git.kernel.org/pub/scm/utils/cpu/mce/mce-test.git
# #git://git.kernel.org/pub/scm/utils/cpu/mce/mce-inject.git
# page-types.c taken from kernel-doc-2.6.32-19.el6:
#   /usr/share/doc/kernel-doc-2.6.32/Documentation/vm/page-types.c

#TARGET_INJECT=mce-inject.git-20100401
#TARGET_TEST=mce-test.git-20110519
TARGET_TEST=/opt/mce-test
TARGET_LTP=/opt/ltp
MCE_INCLUDE=/mnt/tests/kernel/mce-test/include
ping -c 1 download.devel.redhat.com >/dev/null 2>&1 || URL_SFX=.devel.redhat.com

SERVICENAME=''
if `grep -q 'release 6\.' /etc/redhat-release`; then
        SERVICENAME='mcelogd'
else
        # RHEL7 and later
        SERVICENAME='mcelog'
fi

InstallMceInject()
{
    # RHEL6.1 used to have mce-inject in ras-utils but newer RHELs
    # do not have it anymore.
    # yum install -y -q ras-utils

    which "mce-inject" >/dev/null 2>&1
    if [ "$?" == "0" ] ; then
        echo "mce-inject binary already exists, continuing"
        return 0
    fi

    echo "Downloading and compiling mce-inject..."
    mceinjectdir=`mktemp -d`
    echo "    $mceinjectdir"

    pushd "$mceinjectdir"
    git clone "https://git.kernel.org/pub/scm/utils/cpu/mce/mce-inject.git/"
    cd mce-inject
    make install
    popd
    rm -rf "$mceinjectdir"

    which "mce-inject" 2>&1 >/dev/null
    if [ "$?" != "0" ] ; then
        echo "Could not properly install mce-inject, exiting"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
}


InstallMceTest()
{
    which "page-types" >/dev/null 2>&1
    if [ "$?" == "0" ]; then
        echo "mce-test seems to be already available (page-types binary exists), continuing"
        return 0
    fi

    echo "Downloading and compiling mce-test..."

    pushd "/opt"
    git clone "https://github.com/andikleen/mce-test.git"
    if [ "$?" != "0" ] ; then
        echo "Failed to fetch mce-test from git"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
    cd "mce-test"
    pushd tools
    make install
    popd
    cp bin/* /usr/local/bin/
    popd

    which "page-types" >/dev/null 2>&1
    if [ "$?" == "0" ]; then
        echo "Could not properly install mce-test, exiting"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi

    # old code using lookaside (probably obsolete)
    # if [ -f $TARGET_TEST/tsrc/tinjpage ]; then
    #     echo "mce-test already exists, continuing"
    #     return 0
    # else
    #     echo "Installing mce-test..."
    #     wget -q http://download${URL_SFX}/qa/rhts/lookaside/$TARGET_TEST.tar.bz2
    #     tar -jxf $TARGET_TEST.tar.bz2
    #     patch -p1 -d $TARGET_TEST < $MCE_INCLUDE/tinjpage-fix.patch
    #     patch -p1 -d $TARGET_TEST < $MCE_INCLUDE/random-offline-fix.patch
    #     make -C $TARGET_TEST
    # fi

    # if [ ! -f $TARGET_TEST/tsrc/tinjpage ]; then
    #     echo "Failed to install mce-test, exiting"
    #     report_result "$TEST/setup" "FAIL"
    #     exit 0
    # fi
}


InstallPageTypes()
{
    if [ -f /usr/bin/page-types ]; then
        echo "page-types already exists, continuing"
        return 0
    else
        echo "Installing page-types..."
        gcc -o /usr/bin/page-types $MCE_INCLUDE/page-types.c
    fi

    if [ ! -f /usr/bin/page-types ]; then
        echo "Failed to install page-types, exiting"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
}


InstallLTP()
{
   if [ -f /opt/ltp/pan/ltp-pan ]; then
        echo "LTP seems already installed (/ltp/pan/ltp-pan exists), continuing"
        return 0
    fi

    echo "Downloading and compiling LTP..."

    pushd "/opt"
    git clone https://github.com/linux-test-project/ltp.git
    if [ "$?" != "0" ] ; then
        echo "Failed to fetch LTP from git"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
    cd ltp
    make autotools
    if [ "$?" != "0" ] ; then
        echo "LTP 'make autotools' failed"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
    ./configure
    if [ "$?" != "0" ] ; then
        echo "LTP './configure' failed"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
    cd pan
    make
    if [ "$?" != "0" ] ; then
        echo "ltp_pan make failed"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
    popd

    if [ ! -f /opt/ltp/pan/ltp-pan ] ; then
        echo "Could not properly install ltp-pan, exiting"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
}


MountDebugfs()
{
    echo "Mounting debugfs..."
    if [ `mount| grep -c "/sys/kernel/debug type debugfs"` -lt 1 ]; then
        if ! `mount -t debugfs none /sys/kernel/debug/`; then
            echo "Unable to load mount debugfs, exiting"
            report_result "$TEST/setup" "FAIL"
            exit 0
        fi
    fi
}

CreateHugepages()
{
    echo "Creating hugepages..."
    if ! which huge_page_setup_helper.py >/dev/null 2>&1; then
        echo "Failed to find huge_page_setup_helper.py, exting"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
    huge_page_setup_helper.py <<EOF
512
hugepages
hugepages root
EOF
}

MountHugetlbfs()
{
    echo "Mounting hugetlbfs..."
    if ! hugeadm --create-mount; then
        echo "Unable to mount hugetlbfs, exiting"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
}

LoadMceInjectMod()
{
    echo "Loading mce-inject module..."
    if ! `modprobe mce-inject`; then
        echo "Unable to load mce-inject module, exiting"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
}


LoadHwpoisonInjectMod()
{
    echo "Loading hwpoison-inject module..."
    if ! `modprobe hwpoison-inject`; then
        echo "Unable to load hwpoison-inject module, exiting"
        report_result "$TEST/setup" "FAIL"
        exit 0
    fi
}

ResetHugetlbfs()
{
    echo "Clearing hugepages..."
    hugeadm --pool-pages-max 2MB:0
    echo "Umounting hugetlbfs..."
    umount -a -t hugetlbfs
}

UmountDebugfs()
{
    echo "Unmounting debugfs..."
    umount -a -t debugfs
}

GenRandAddr()
{
    # Generate a random (fake) address to inject. Note: leading zeros on injected
    # addresses are truncated by the kernel, which means grepping for that address in
    # logs will fail. For simplicity, just don't generate addresses starting with
    # "0".
    local addr=`uuidgen |cut -f1 -d'-'`
    echo $addr |grep -q '^0'
    if [ $? -eq 0 ]; then
        # Recursive call. Try generating a new one.
        GenRandAddr
    else
        echo $addr
    fi
}
