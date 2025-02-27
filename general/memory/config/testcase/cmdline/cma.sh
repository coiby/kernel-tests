#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: For details, check bug 1945002 on bugzilla.
#   Author: Shizhao Chen <shichen@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc. All rights reserved.
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
#
#   This case is based on <dhildenb@redhat.com>'s instruction from the
#   bugzilla thread, main steps taken in this case is listed below:
#
#   1. Define hugetlb_cma & cma cmdline args;
#
#   2. Consume most available memory with memtester for shuffling free
#      page lists;
#
#   3. Stop the memtester pocess before it's finished;
#
#   4. Run a workload that leaves roughly 2G memory in the system;
#
#   5. Try allocating 2G gigantic pages;
#
#   6. Observe if allocation succeeded.
#
#   If failed allocating, then retry step 5 and 6 several times, 10
#   times in this case.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

free_mem=`awk '/^Mem/ {print $4}' <(free -m)`

function hugepage_alloc()
{
    # Size(GB) of gigantic pages for allocation.
    local size=2
    local hugepages_1g="/sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages"
    local dir_memtester="/mnt/tests/kernel/memory/memtester4"

    rlRun "dnf install -y kernel-memory-memtester4"
    rlRun "dnf install -y patch"

    # Select subcases in memtester used to do the shuffling,
    # concerning running the whole set of cases would be too
    # time-consuming.
    sed -i '/    { "Compare/d; /    { "Solid/d; /    { "Check/d; /    { "Bit/d; /    { "Walking/d;' $dir_memtester/memtester.c

    rlRun "pushd $dir_memtester && make build; popd"

    # Step 2, 3
    if ((partial_shuffle)); then
        rlRun "timeout 120 $dir_memtester/memtester `echo "$free_mem - 500" | bc` 1" 0-255
    else
        rlRun "$dir_memtester/memtester `echo "$free_mem - 500" | bc` 1"
    fi
    # Step 4
    rlRun "$dir_memtester/memtester `echo "$free_mem - $size * 1024 - 500" | bc` 1>/dev/null &"

    sleep 30s

    find /sys/kernel/mm/cma/ -type f -printf "%p:" -a -exec cat {} \;

    # Step 5, 6
    alloc_times=10
    for i in $(seq $alloc_times); do
        echo $size > $hugepages_1g
        if [ $i = 10 ]; then
            rlAssertEquals "Assert the value of 1G nr_hugepages is equal to $size." $(cat $hugepages_1g) $size
        elif [ $(cat $hugepages_1g) -eq $size ]; then
            rlPass "Successfully allocated ${size}G gigantic pages."
            echo 0 > $hugepages_1g
            break
        fi
        echo 0 > $hugepages_1g
        sleep 60s
    done

    find /sys/kernel/mm/cma/ -type f -printf "%h:" -a -exec cat {} \;

    pkill "memtester"
}

function cma()
{
    # The upper limit of memory, accepts value from CLI, default 8000.
    if [ "$MAX_MEM" ]; then
        max_mem=$MAX_MEM
    else
        max_mem=8192
    fi

    if rlIsRHEL "<9"; then
        rlLog "Only for RHEL9+."
        rstrnt-report-result "cma" SKIP
        return
    fi

    if [ "$(rlGetPrimaryArch)" != "x86_64" ]; then
        rlLog "Only for x86_64."
        rstrnt-report-result "cma" SKIP
        return
    fi

    # This case tests 2G hugapeges' alloc. Lower limit set to 4096.
    if [ $free_mem -lt 4096 ]; then
        rlLog "Memory too small, should be more than 4096MB."
        rstrnt-report-result "cma" SKIP
        return
    fi

    # `memtester` costs 1hr+ for per GB workload.
    if [ $free_mem -gt $max_mem ]; then
        rlLog "Memory too large, greater than ${max_mem}MB, will partially shuffle free page lists"
        partial_shuffle=1
        cma_args=" cma=1G"
    fi

    if ! grep CONFIG_CMA=y /boot/config-*; then
        rlLog "CONFIG_CMA not enabled."
        rstrnt-report-result "cma" SKIP
        return
    fi

    if ! lscpu | grep pdpe1gb 1>/dev/null; then
        rlLog "This CPU doesn't support 1G hugepages."
        rstrnt-report-result "cma" SKIP
        return
    fi

    # Step 1
    setup_cmdline_args "hugetlb_cma=2G $cma_args" bz1945002
    # Step 2-6
    hugepage_alloc
    cleanup_cmdline_args "hugetlb_cma cma"
}

