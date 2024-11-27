#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/vm/hugepage/ltp-hugetlbfs
#   Description: Porting hugetlbfs tests from ltp to RHTS
#   Author: Caspar Zhang <czhang@redhat.com>
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

# Enable TMT testing for RHIVOS
. ../../../automotive/include/rhivos.sh
declare -F kernel_automotive && kernel_automotive && is_rhivos=1 || is_rhivos=0

if ! (($is_rhivos)); then
    # Include rhts environment
    . /usr/bin/rhts-environment.sh || exit 1
fi

. ../../../distribution/ltp/include-ng/include.sh	|| exit 1

trap 'trap "" EXIT; TearDown' EXIT
HPAGE=/proc/sys/vm/nr_hugepages
MEM_LEFT=64
RESULT=PASS

TearDown()
{
    echo 0 > ${HPAGE}
}

function TestBuild()
{
        # The test could be running on different path
        # Just skip the build, but make sure the config is copied
        if [ -f ${LTPDIR}/runltp ]; then
                echo "LTP has been built and installed at ${LTPDIR}/runltp !"
                return
        fi

        build_all
}

SetupHugetlb()
{
    if ! grep 'hugetlbfs' /proc/filesystems; then
        echo "[FAIL] This machine is not configured with hugetlb" | tee -a ${OUTPUTFILE}
        RESULT=FAIL
        return
    fi

    echo " - Show /proc/meminfo (before setup):" | tee -a ${OUTPUTFILE}
    echo "========================="
    cat /proc/meminfo
    echo "========================="

    if [ "${TESTVERSION}" -ge 20240930 ]; then
        cat hugetlb.inc.new > HUGEPAGE
    else
        cat hugetlb.inc > HUGEPAGE
    fi

    Hugepagesize=$(echo `grep 'Hugepagesize:' /proc/meminfo | awk '{print $2}'` / 1024 | bc)
    # Calculate nr_hugepages to allocate
    # try to allocate 1GB / Hugepagesize -> if fail ->
    # try to allocate as much as we can (leave $MEM_LEFT MB for other use)
    echo " - Calculate memory to be reserved for hugepages" | tee -a ${OUTPUTFILE}
    MemFree=$(echo `grep 'MemFree:' /proc/meminfo | awk '{print $2}'` / 1024 - $MEM_LEFT | bc)
    MemAlloc="$MemFree"
    if [ "$MemFree" -gt "1024" ]; then
        MemAlloc=1024
    elif [ "$MemFree" -le "0" ]; then
        echo "[SKIP] No enough memory for testing" | tee -a ${OUTPUTFILE}
        rstrnt-report-result Test_Skipped PASS 99
        exit 0
    fi
    if [ "${ARCH}" = "s390x" ]; then
        if  [ "$MemFree" -gt "128" ]; then
            MemAlloc=128 # only allocate 128MB on s390x
        else
            echo "the MemFree is too small to test"
                rstrnt-report-result Test_Skipped PASS 99
                exit 0
        fi
    fi
    NR_HPAGE=`echo $MemAlloc / $Hugepagesize | bc`
    # Finally we calculated how many hugepages we'll allocate
    sed -i "s/#nr_hpage#/$NR_HPAGE/g" HUGEPAGE

    # hugemmap05 test is a little different
    MemAllocOvercommit=`echo $MemFree / 5 | bc`
    if [ "$MemAllocOvercommit" -gt "128" ]; then # No more than 128MB
        # reserve MemAllocOvercommit for hugepage_size = 512MB system(eg. rhel_alt aarch64)
        if [ "x${Hugepagesize}" != "x512" ]; then
            MemAllocOvercommit=128
        fi
    fi
    NR_HUGEMMAP5=`echo $MemAllocOvercommit / $Hugepagesize | bc`
    sed -i "s/#size#/${NR_HUGEMMAP5}/g" HUGEPAGE

    # hugemmap06 need more than 255 hugepages
    NR_HUGEMMAP6=`echo $MemFree / $Hugepagesize | bc`
    if [ "$NR_HUGEMMAP6" -lt "256" ]; then
        sed -i "s/hugemmap06//g" HUGEPAGE
    fi
}

# ---------- Start Test -------------

echo "============ Setup ============"

cat /proc/filesystems | grep -q hugetlbfs
if [ $? -ne 0 ]; then
    # Bug 1143877 - hugetlbfs: disabling because there are no supported hugepage sizes
    echo "hugetlbfs not found in /proc/filesystems, skipping test"
    rstrnt-report-result Test_Skipped PASS 99
    exit 0
fi

TestBuild
SetupHugetlb

rstrnt-report-result "${TEST}/Setup" "${RESULT}"

DisableNTP

echo "============ Start to test hugetlb ============"

t=HUGEPAGE
cp $t $LTPDIR/runtest

CleanUp $t

OUTPUTFILE=`mktemp /tmp/tmp.XXXXXX`

RunTest $t

EnableNTP

echo "============================="
cat /proc/meminfo
echo "============================="

exit 0
