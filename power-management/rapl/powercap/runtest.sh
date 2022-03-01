#!/bin/bash
#
# Copyright (c) 2019 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#

FILE=$(readlink -f $BASH_SOURCE)
CDIR=$(dirname $FILE)
TMPDIR=/var/tmp/$(date +"%Y%m%d%H%M%S")

source $CDIR/../../common/libpwmgmt.sh

# XXX: This function is from power-management/rapl/powercap/cap.sh
function set_cap
{
    typeset energy=${1?"*** energy_in_microjoules***"}
    typeset cpu_sockets=$(lscpu | grep 'Socket(s):' | \
                          sed 's/^Socket(s):[^0-9]*\([0-9]*\)/\1/')
    typeset cap_energy=$(( energy / cpu_sockets ))
    typeset rapl_path="/sys/devices/virtual/powercap/intel-rapl"
    typeset rapl=$(ls -1 $rapl_path | grep 'intel-rapl:')
    typeset cpu=""
    for cpu in $rapl; do
        echo $cap_energy > $rapl_path/$cpu/constraint_0_power_limit_uw
    done
}

# XXX: This function is from power-management/rapl/powercap/read_cap.sh
function get_cap
{
    typeset rapl_path="/sys/devices/virtual/powercap/intel-rapl"
    typeset rapl=$(ls -1 "$rapl_path" | grep 'intel-rapl:')

    typeset cpu=""
    typeset e=0
    for cpu in $rapl; do
        e_cpu=$(cat $rapl_path/$cpu/constraint_0_power_limit_uw)
        (( e += e_cpu ))
    done

    echo $e
}

# XXX: This function is from power-management/rapl/powercap/energy.sh
function get_energy
{
    typeset time=${1:-"30"} # Default is 30 secs
    typeset rapl_path="/sys/devices/virtual/powercap/intel-rapl"
    typeset rapl=$(ls -1 "$rapl_path" | grep 'intel-rapl:')

    typeset cpu=""
    typeset e1=0
    for cpu in $rapl; do
        typeset e_cpu=$(cat "$rapl_path/$cpu/energy_uj"*)
        (( e1 += e_cpu ))
    done

    sleep $time

    typeset e2=0
    for cpu in $rapl; do
        typeset e_cpu=$(cat "$rapl_path/$cpu/energy_uj"*)
        (( e2 += e_cpu ))
    done

    typeset e=$(( (e2 - e1) / time ))
    echo $e
}

# XXX: This function is from power-management/rapl/powercap/load1.sh
function load1
{
    typeset sleeptime=${1:-"1"}

    # do some load
    dd if=/dev/zero > /dev/null 2>&1 &
    typeset loadpid=$!

    sleep $sleeptime
    # wait a bit longer, than length of test
    sleep 10

    # kill the load
    kill -9 $loadpid
}

# XXX: This function is from power-management/rapl/powercap/load_m.sh
function loadm
{
    typeset -i timeout=$1
    typeset -i nthreads=$2
    typeset -i i
    for (( i = 0; i < $nthreads; i++ )); do
        (load1 $timeout) > /dev/null 2>&1 &
        typeset pid=$!
        rlLog "load1[$i] is started, pid=$pid"
    done
}

# XXX: This function is from power-management/rapl/powercap/test_capping.sh
function test_capping
{
    # measurement time should be bigger than
    # cat /sys/devices/virtual/powercap/intel-rapl/intel-rapl\:0/constraint_0_time_window_us
    # which is 1 sec by default (at least on systems I have seen so far).
    typeset measurement_time=30
    typeset load_time=$(( measurement_time + 20 ))

    # 1. no load, no cap
    typeset e_no_no=$(get_energy $measurement_time)
    rlLog "Power consumtion on uncapped system with no load: $e_no_no microwatts"

    # 2. load, no cap
    typeset cpus=$(lscpu | grep '^CPU(s):' | \
                   sed 's/^CPU(s):[^0-9]*\([0-9]*\)/\1/')
    loadm $load_time $cpus
    typeset e_full_no=$(get_energy $measurement_time)
    rlLog "Power consumtion on uncapped system with full load: $e_full_no microwatts"

    # 3. cap to average between full load and no load
    typeset e_mid=$(( (e_no_no + e_full_no) / 2 ))
    rlLog "Going to cap the system to: $e_mid microwatts"

    typeset old_cap=$(get_cap)
    set_cap $e_mid
    loadm $load_time $cpus
    typeset e_full_cap=$(get_energy $measurement_time)
    rlLog "Power consumtion on capped system with full load: $e_full_cap microwatts"

    #
    # measured_max is maximal measured value which will not cause fail
    # measured_min is minimal measured value which will not cause fail
    # *11/10 - add 10% in bash which works in integers only - we're
    # using microwatts, so numbers are milions to hundreds of milions,
    # so tehre is no problem with rounding error
    # *9/10 - substract 10%
    #
    typeset measured_max=$(( e_mid * 11 / 10 ))
    typeset measured_min=$(( e_mid *  9 / 10 ))

    rlLog "capping back to $old_cap"
    set_cap $old_cap

    rlLog "e_no_no      = $e_no_no"
    rlLog "e_full_no    = $e_full_no"
    rlLog "e_mid        = $e_mid"
    rlLog "e_full_cap   = $e_full_cap"
    rlLog "measured_max = $measured_max"
    rlLog "measured_min = $measured_min"
    if (( e_full_cap > measured_max || e_full_cap < measured_min )); then
        rlLog "FAIL: measured energy consumption doesn't match capped value"
        return 1
    fi

    return 0
}

function startup
{
    is_kvm
    if (( $? == 0 )); then
        cki_beakerlib_skip_task "kvm is unsupported"
    fi

    is_intel
    if (( $? != 0 )); then
        cki_beakerlib_skip_task "non-intel CPU is unsupported"
    fi

    has_kmod_intel_rapl
    if (( $? != 0 )); then
        cki_beakerlib_skip_task "kernel module 'intel-rapl' is not loaded"
    fi

    if [[ ! -d $TMPDIR ]]; then
        rlRun "mkdir -p -m 0755 $TMPDIR" || return $CKI_UNINITIATED
    fi

    return $CKI_PASS
}

function cleanup
{
    rlRun -l "rm -rf $TMPDIR" "0-255"
    return $CKI_PASS
}

function HW_good {
    hw_problems=0
    if cpupower frequency-info | grep 'current CPU frequency:' | grep -q 'Unable to call to kernel'; then
        echo "Skipping test due to H/W return invalid current CPU frequency"
        (( hw_problems+=1 ))
    fi
    if cpupower frequency-info | grep -q 'no or unknown cpufreq driver is active on this CPU'; then
        echo "Skipping test due to H/W return invalid cpufreq driver"
        (( hw_problems+=1 ))
    fi
    if [ "$hw_problems" -gt 0 ]; then
       rstrnt-report-result "rapl/powermanagement" SKIP
       exit 0
    fi
}

function runtest
{
    # For debugging
    rlRun -l "find /sys/devices/ -name *rapl*" "0-255"
    rlRun -l "lsmod" "0-255"

    # check if HW supports known cpufreq driver and returns the frequency to the standard tools
    HW_good

    # Check if capping works, it should take approx 1.5 - 2 minutes
    test_capping || return $CKI_FAIL
    return $CKI_PASS
}

cki_main
exit $?
