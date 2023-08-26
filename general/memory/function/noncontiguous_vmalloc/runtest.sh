#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Use kmod to test vmallocinfo & meminfo
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

. /usr/share/beakerlib/beakerlib.sh
. ../../../../cki_lib/libcki.sh

get_vmallocused="grep -i vmallocused /proc/meminfo | tr -cd [:digit:]"
get_memtotal="grep -i memtotal /proc/meminfo | tr -cd [:digit:]"
get_memfree="grep -i memfree /proc/meminfo | tr -cd [:digit:]"
variation=0
mod_inserted=0
before_inserted=0
after_inserted=0
after_removed=0
used=0
PAGESIZE=$(getconf PAGESIZE)
PAGENUM=1024

kname="kernel"
if cki_is_kernel_rt; then
    kname="kernel-rt"
fi
if cki_is_kernel_automotive; then
    kname="kernel-automotive"
fi
if cki_is_kernel_debug; then
    kname="${kname}-debug"
fi
kversion=$(uname -r | awk -F '-' '{print $1}')
krelease=$(uname -r | awk -F '-' '{print $2}')
krelease=${krelease%.*}
karch=$(uname -m)

(( allocated = PAGESIZE * PAGENUM / 1024 ))

function cat_procfs()
{
    flag="before_inserted"
    case $1 in
        1)
            flag="after_inserted"
            ;;
        2)
            flag="after_removed"
            ;;
    esac
    echo "=== cat /proc/meminfo ${flag} ==="
    cat /proc/meminfo
    if [ -e /proc/vmallocinfo ]; then
        echo "=== cat /proc/vmallocinfo ${flag} ==="
        cat /proc/vmallocinfo
    fi
}

function get_variation_stat()
{
    echo "Please wait 1min..."
    local tmp_min=$(eval $get_vmallocused)
    local tmp_max=$(eval $get_vmallocused)
    for i in {1..600}; do
        local tmp=$(eval $get_vmallocused)
        [ $tmp -lt $tmp_min ] && tmp_min=$tmp
        [ $tmp -gt $tmp_max ] && tmp_max=$tmp
        sleep 0.1s
    done
    (( variation = tmp_max - tmp_min ))
}

# Get current variation, use it to determine the PAGENUM of pages to
# allocate. Two rules are followed here:
#
# 1. allocated should -gt variation;
# 2. allocated + variation should -lt memfree;
#
# Rule#1 is a soft rule, and rule#2 is a hard rule to avoid oom. The
# current approach will try to satisfy both, when that is not
# possible, rule#1 will be comprimised.
function get_pagenum()
{
    get_variation_stat

    while [ $variation -gt $allocated ]; do
        (( PAGENUM += 1024 ))
        (( allocated = PAGESIZE * PAGENUM / 1024 ))
    done

    local tmp_memfree=$(eval $get_memfree)
    (( half_memfree = tmp_memfree / 2 ))
    (( half_variation = variation / 2))
    # avoid causing oom
    if [ $variation -gt $half_memfree ]; then
        PAGENUM=$(echo "(${tmp_memfree} - ${variation}) * 1024 / ${PAGESIZE}" | bc)
        (( allocated = PAGESIZE * PAGENUM / 1024 ))
        if [ $allocated -lt $half_variation ]; then
            rlLog "Current variation too high: ${variation}. Using ${PAGENUM} as PAGENUM. Potential failure may be caused."
            echo -e "memtotal: $(eval $get_memtotal)\nmemfree: ${tmp_memfree}\nvariation: ${variation}\nallocated: ${allocated}"
        fi
    fi
}

function assert_allocated()
{
    case $1 in
        1)
            (( used = after_inserted - before_inserted ))
            ;;
        2)
            (( used = after_inserted - after_removed ))
            ;;
    esac
    (( allocated = PAGENUM * PAGESIZE / 1024 ))
    ratio=$(printf "%.0f" $(echo "scale=2; ${allocated}/${used}" | bc))
    if [ $ratio -eq 1 ]; then
        true
    else
        false
    fi
}

function vmalloc_test_setup()
{
    # check if nvr in 4.4.0-5.3.0
    if stat /run/ostree-booted > /dev/null 2>&1; then
        rlRun "rpm-ostree -y -A --idempotent --allow-inactive install rpmdevtools"
    else
        yum install -y rpmdevtools
    fi
    newer_than_4=$(rpmdev-vercmp 4.4.0 $(uname -r) 1>/dev/null; echo $?)
    older_than_5=$(rpmdev-vercmp $(uname -r) 5.3.0 1>/dev/null; echo $?)

    # skip on non-x86 cki kernel builds
    if ! uname -r | grep -q x86_64 && uname -r | grep -E "mr[0-9]+"; then
        rstrnt-report-result "vmalloc_cki_module_compile" SKIP
        rlPhaseEnd
        exit 0
    fi
    # skip if not supported, fail on other occasions and then continue
    if [ "$(eval $get_vmallocused)" = "0" ]; then
        cat_procfs 0
        if [ $(( newer_than_4 + older_than_5 )) -eq 24 ]; then
            rstrnt-report-result "vmallocused_not_supported" SKIP
            rlPhaseEnd
            exit 0
        else
            rlFail "VmallocUsed is 0, but it shouldn't be."
        fi
    fi

    # install kernel-devel pkg
    if ! cki_is_kernel_automotive; then
        rlRun "yum install -y ${kname}-devel-$(uname -r) || ../../../include/scripts/wget-kernel.sh --running --devel -i"
    else
        if ! rpm -q --quiet ${kname}-devel-$(uname -r | sed -e 's/+debug//'); then
            if stat /run/ostree-booted > /dev/null 2>&1; then
                rlRun "rpm-ostree -y -A --idempotent --allow-inactive install ${kname}-devel-${kversion}-${krelease}.${karch}"
            else
                rlRpmInstall ${kname}-devel ${kversion} ${krelease} ${karch}
            fi
        fi
    fi

    get_pagenum
}

# Description:
# [before] inserted [after]-[before] removed [after]
#
# Three phases separated by two actions: insert and remove. This
# function contains the complete process in five loops. Report fail if
# the last loop fails. Otherwise report pass and break loop.
#
# Each phase has a corresponding global variable - they are updated
# before each phase begins. variation & pagenum should be updated
# before each loop begins.
function vmalloc_test_run()
{
    [ -d /sys/module/vmalloc_test ] && rmmod vmalloc_test
    pass_flag=1
    for i in {1..5}; do
        [ ! $i -eq 1 ] && get_pagenum
        # phase#1 - before module inserted
        if [ $mod_inserted -eq 0 ]; then
            before_inserted=$(eval $get_vmallocused)
            BKRARCH=$ARCH; unset ARCH
            cat_procfs 0
            rlLog "before_inserted: ${before_inserted}; variation: ${variation}; allocated: ${allocated}"
            rlRun "pushd module && make"
            rlRun "insmod vmalloc_test.ko vm_buf_size=$PAGENUM"
            [ -d /sys/module/vmalloc_test ] && mod_inserted=1
            make clean
            popd
            export ARCH=$BKRARCH
        fi
        if [ $i -eq 5 ] && [ $mod_inserted -eq 0 ]; then
            rlFail "Fail to insert module."
        fi
        # phase#2 - after module inserted
        if [ $mod_inserted -eq 1 ]; then
            sleep 1s
            cat_procfs 1
            after_inserted=$(eval $get_vmallocused)
            if assert_allocated 1; then
                rlPass "Pass assertion on memory allocation."
                pass_flag=1
            elif [ $i -eq 5 ]; then
                rlFail "Fail assertion on memory allocation."
            else
                pass_flag=0
            fi
            rlLog "after_inserted: ${after_inserted}; variation: ${variation}; allocated: ${allocated}"

            # phase#3 - after module removed
            rlRun "rmmod vmalloc_test"
            sleep 1s
            cat_procfs 2
            after_removed=$(eval $get_vmallocused)
            if assert_allocated 2; then
                rlPass "Pass assertion on memory freeing."
            elif [ $i -eq 5 ]; then
                rlFail "Fail assertion on memory freeing."
            else
                pass_flag=0
            fi
            rlLog "after_removed: ${after_removed}; variation: ${variation}; allocated: ${allocated}"
            [ ! -d /sys/module/vmalloc_test ] && mod_inserted=0
            [ $pass_flag -eq 1 ] && break
        fi
    done
}

rlJournalStart
    rlPhaseStartSetup
        vmalloc_test_setup
    rlPhaseEnd

    rlPhaseStartTest
        rlAssertLesserOrEqual "Assert VmallocUsed -lt MemTotal." $(eval $get_vmallocused) $(eval $get_memtotal)
        vmalloc_test_run
    rlPhaseEnd

    rlJournalPrintText
rlJournalEnd
