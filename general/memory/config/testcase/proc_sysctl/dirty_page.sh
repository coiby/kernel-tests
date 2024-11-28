#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: TestCaseComment
#   Author: Wang Shu <shuwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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

function test_dirty_bytes1()
{
    rlLog "Start ${FUNCNAME[0]}"
    rlRun "sysctl -w vm.dirty_background_bytes=500000000"
    rlRun "sysctl -w vm.dirty_bytes=500000000"
    rlAssert0 "dirty_background_ratio" $(sysctl -n vm.dirty_background_ratio)
    rlAssert0 "dirty_ratio" $(sysctl -n vm.dirty_ratio)

    rlRun "sync && sysctl -w vm.drop_caches=3"
    rlRun "dd if=/dev/zero of=./testfile bs=1M count=200"
    sleep 10
    rlAssertGreaterOrEqual "200M should not trigger flush since dirty_bytes are set to 500M" "$(awk '/Dirty/ {print $2}' /proc/meminfo)" "$((204800/10*8))"
    rlRun "rm -f ./testfile"
}

function test_dirty_bytes2()
{
    rlLog "Start ${FUNCNAME[0]}"
    rlRun "sysctl -w vm.dirty_background_bytes=1000000"
    rlRun "sysctl -w vm.dirty_bytes=1000000"
    rlAssert0 "dirty_background_ratio" $(sysctl -n vm.dirty_background_ratio)
    rlAssert0 "dirty_ratio" $(sysctl -n vm.dirty_ratio)

    rlRun "sync && sysctl -w vm.drop_caches=3"
    rlRun "dd if=/dev/zero of=./testfile bs=1M count=200"
    sleep 10
    rlAssertGreaterOrEqual "200M should trigger flush since dirty_bytes are set to 1M" "10240" "$(awk '/Dirty/ {print $2}' /proc/meminfo)"
    rlRun "rm -f ./testfile"
}

function test_dirty_ratio1()
{
    rlLog "Start ${FUNCNAME[0]}"
    rlRun "sysctl -w vm.dirty_background_ratio=20"
    rlRun "sysctl -w vm.dirty_ratio=20"
    rlAssert0 "dirty_background_bytes" $(sysctl -n vm.dirty_background_bytes)
    rlAssert0 "dirty_bytes" $(sysctl -n vm.dirty_bytes)

    local memtotal="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    local watermark="$((memtotal/100*20))"
    local watermark_low="$((memtotal/100*10))"
    local watermark_high="$((memtotal/100*30))"

    if ! test_get_diskfreek; then
        rstrnt-report-result "${FUNCNAME[0]}-disk_unknown" SKIP
        return
    elif (($(test_get_diskfreek) < memtotal)); then
        rstrnt-report-result "${FUNCNAME[0]}-disk_space" SKIP
        return
    fi

    rlRun "sync && sysctl -w vm.drop_caches=3"
    rlRun "dd if=/dev/zero of=./testfile bs=1K count=$watermark_low"
    sleep 10
    rlAssertGreaterOrEqual "10% dirty pages should not trigger flush since dirty_ratio=20" "$(awk '/Dirty/ {print $2}' /proc/meminfo)" $((watermark_low/10*8))
    rlRun "rm -f ./testfile"
}

function test_dirty_ratio2()
{
    rlLog "Start ${FUNCNAME[0]}"
    rlRun "sysctl -w vm.dirty_background_ratio=20"
    rlRun "sysctl -w vm.dirty_ratio=20"
    rlAssert0 "dirty_background_bytes" $(sysctl -n vm.dirty_background_bytes)
    rlAssert0 "dirty_bytes" $(sysctl -n vm.dirty_bytes)


    local memtotal="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    local watermark="$((memtotal/100*20))"
    local watermark_low="$((memtotal/100*10))"
    local watermark_high="$((memtotal/100*30))"

    if ! test_get_diskfreek; then
        rstrnt-report-result "${FUNCNAME[0]}-disk_unknown" SKIP
        return
    elif (($(test_get_diskfreek) < memtotal)); then
        rstrnt-report-result "${FUNCNAME[0]}-disk_space" SKIP
        return
    fi

    rlRun "sync && sysctl -w vm.drop_caches=3"
    rlRun "dd if=/dev/zero of=./testfile bs=1K count=$watermark_high"
    sleep 10
    rlAssertGreaterOrEqual "30% dirty pages should trigger flush since dirty_ratio=20" $watermark "$(awk '/Dirty/ {print $2}' /proc/meminfo)"
    rlRun "rm -f ./testfile"
}


function test_dirty_expire_centisecs1()
{
    rlLog "Start ${FUNCNAME[0]}"
    rlRun "sysctl -w vm.dirty_expire_centisecs=1000"
    rlRun "sysctl -w vm.dirty_writeback_centisecs=100"

    rlRun "sysctl -w vm.dirty_background_bytes=500000000"
    rlRun "sysctl -w vm.dirty_bytes=500000000"

    rlRun "sync && sysctl -w vm.drop_caches=3"
    rlRun "dd if=/dev/zero of=./testfile bs=1M count=200"
    sleep 5
    rlAssertGreaterOrEqual "5s should not trigger flush since vm.dirty_expire_centisecs=1000" "$(awk '/Dirty/ {print $2}' /proc/meminfo)" "$((204800/10*8))"
    sleep 10
    rlAssertGreaterOrEqual "15s should trigger flush since vm.dirty_expire_centisecs=1000" "204800" "$(awk '/Dirty/ {print $2}' /proc/meminfo)"
    rlRun "rm -f ./testfile"
}

dirty_page()
{
    swapoff -a
    #local dirty_background_bytes=$(sysctl -n vm.dirty_background_bytes)
    #local dirty_bytes=$(sysctl -n vm.dirty_bytes)
    local dirty_background_ratio=$(sysctl -n vm.dirty_background_ratio)
    local dirty_expire_centisecs=$(sysctl -n vm.dirty_expire_centisecs)
    local dirty_ratio=$(sysctl -n vm.dirty_ratio)
    local dirty_writeback_centisecs=$(sysctl -n vm.dirty_writeback_centisecs)

    rlRun "sysctl -w vm.dirty_writeback_centisecs=0"

    test_dirty_bytes1

    test_dirty_bytes2

    test_dirty_ratio1

    test_dirty_ratio2

    test_dirty_expire_centisecs1


    rlRun "sysctl -w vm.dirty_background_ratio=${dirty_background_ratio}"
    rlRun "sysctl -w vm.dirty_ratio=${dirty_ratio}"
    rlRun "sysctl -w vm.dirty_expire_centisecs=${dirty_expire_centisecs}"
    rlRun "sysctl -w vm.dirty_writeback_centisecs=${dirty_writeback_centisecs}"

    swapon -a
}
