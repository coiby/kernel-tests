#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: TestCaseComment
#   Author: Wang Shu <shuwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2014 Red Hat, Inc.
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

zone_reclaim_mode()
{
    local total_freemem freemem_cached freemem_new
    local nr_nodes=$(numactl -H | awk 'BEGIN{total=0} /node [0-9]+ size/ && $4 > 0 {total++}END{print total}')
    ((nr_nodes > 1))
    if [ $? != 0 ]; then
        rlLog "Skip, at least requires 2 numa nodes."
        return 0;
    fi
    rlRun "gcc $DIR_SOURCE/usemem.c -o ./usemem"

    # Step1, fill node0 with file cache
    rlLog "Drop caches and fill node0 with file caches."
    echo 3 >/proc/sys/vm/drop_caches
    total_freemem=`numactl -H | grep 'node 0 free' | awk '{print $4}'`

    if ! test_get_diskfreem; then
        rstrnt-report-result "${FUNCNAME[0]}-disk_unknown" SKIP
        return
    elif (( $(test_get_diskfreem) < total_freemem)); then
        rstrnt-report-result "${FUNCNAME[0]}-disk_space" SKIP
        return
    fi

    rlRun "numactl --physcpubind=0  dd if=/dev/zero of=./trash bs=1M count=$total_freemem"

    # Step2, mark freemem left on node0
    freemem_cached=`numactl -H | grep 'node 0 free' | awk '{print $4}'`
    rlLog "${freemem_cached}M freemem on node0"

    # Step3, alloc 1G mem on node0 when zone_reclaim_mode is disabled
    echo 0 > /proc/sys/vm/zone_reclaim_mode
    rlRun "numactl --physcpubind=0 ./usemem 1024 1 2>&1"
    freemem_new=`numactl -H | grep 'node 0 free' | awk '{print $4}'`

    # Assert usemem didn't reclaim caches on node0
    rlAssertGreaterOrEqual "Assert usemem 1G didn't use caches on node0, freemem=${freemem_new}" $((freemem_cached+100)) $freemem_new

    # Step4, alloc mem on node0 when zone_reclaim_mode is enabled
    freemem_cached=$freemem_new
    echo 1 > /proc/sys/vm/zone_reclaim_mode
    rlRun "numactl --physcpubind=0 ./usemem $((freemem_new*6/5)) 1 2>&1"
    freemem_new=`numactl -H | grep 'node 0 free' | awk '{print $4}'`

    # Assert usemem reclaimed caches on node0.
    #  So when usemem finished, those memory should be released to node0.
    rlAssertGreaterOrEqual "Assert usemem reclaimed caches on node0, freemem=${freemem_new}" $freemem_new $((freemem_cached))

    rm -f ./usemem ./trash

}

