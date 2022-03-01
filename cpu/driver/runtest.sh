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

FILE=$(readlink -f ${BASH_SOURCE})
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)
TEST=${TEST:-"$0"}
TMPDIR=/var/tmp/$(date +"%Y%m%d%H%M%S")

source $CDIR/../../cpu/common/libutil.sh

NON_PSTATE_PROCESSORS="26 31 46"
check_pstate_support()
{
    for m in $NON_PSTATE_PROCESSORS; do
	if [ $m -eq $1 ]; then
	    rlLog "model: $model - does not support intel_pstate"
	    return 1
	fi
    done

    return 0
}

function verify_intel_cpufreq_driver
{
    typeset driver=$1

    rlLog "Start to verify intel cpu freq driver"

    typeset vendor=$(dmidecode -t 0 | grep Vendor: | \
                     cut -d: -f 2 | awk '{print tolower($1)}')

    typeset model=$(lscpu | grep Model: | awk '{print $2}')
    if [ -z "$model" ]; then
	rlLog "unable to determine cpu model"
	return $CKI_FAIL
    fi

    # make sure the given system supports p-state
    check_pstate_support $model
    if [ $? -ne 0 ]; then
	# older systems do not support intel pstate
	if [ $driver != "acpi-cpufreq" ]; then
	    rlLog "intel (non-pstate) system is running: $driver"
	    # maps to SKIP
	    return $CKI_UNSUPPORTED
	fi
	rlLog "intel system is running: $driver"
	return $CKI_PASS
    fi

    if [ $driver != "intel_pstate" ] && [ $driver != "intel_cpufreq" ]; then
	if [ "$vendor" = "lenovo" ]; then
	    rlLog "lenovo intel system is running: $driver"
	    rlLog "PASS"
	    return $CKI_PASS
	fi
        cki_beakerlib_fail "intel system is running: $driver"
        return $CKI_FAIL
    fi

    rlRun -l "lscpu | grep 'hwp '" "0-255"
    if (( $? == 0 )); then
	if [ "$driver" = "intel_pstate" ]; then
            rlRun -l "rdmsr 0x770"
            if (( $? != 0 )); then
                cki_beakerlib_skip_task "intel system has HWP, but it is not enabled"
            fi
	else
            cki_beakerlib_fail "intel system is not running intel_pstate running: $driver"
            return $CKI_FAIL
	fi
    else
        rlRun -l "ls /sys/devices/system/cpu/intel_pstate/"
        if (( $? != 0 )); then
            cki_beakerlib_fail "intel system does not have HWP, intel_pstate is not active"
            return $CKI_FAIL
        fi
    fi

    rlLog "PASS"
    return $CKI_PASS
}

function verify_amd_cpufreq_driver
{
    typeset driver=$1

    rlLog "Start to verify amd cpu freq driver"

    typeset family=$(cat /proc/cpuinfo | grep family | \
                     sort -u | awk '{print $4}')

    # verify family is >= 15h
    if (( $family >= 0x15 )); then
        if [[ $driver != "acpi-cpufreq" ]]; then
            cki_beakerlib_fail "amd system is running: $driver"
            return $CKI_FAIL
        fi
    else
        cki_beakerlib_skip_task "this test is not valid for the AMD family"
    fi

    rlLog "PASS"
    return $CKI_PASS
}

function runtest
{
    typeset vendor_str=$(cat /proc/cpuinfo | grep vendor | \
                         sort -u | awk '{print $3}')

    if [[ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver ]]; then
        typeset driver=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_driver | uniq)
    else
        typeset driver="NONE"
    fi

    case $vendor_str in
    GenuineIntel)
        verify_intel_cpufreq_driver $driver
        typeset -i ret=$?
        ;;

    AuthenticAMD)
        verify_amd_cpufreq_driver $driver
        typeset -i ret=$?
        ;;

    *) # UNSUPPORTED
        cki_beakerlib_skip_task "it is an unsupported vendor: $vendor_str"
        ;;
    esac

    return $ret
}

function startup
{
    if [[ $(virt-what) == "kvm" ]]; then
        cki_beakerlib_skip_task "this test is unsupported in kvm"
    fi

    if [[ ! -d $TMPDIR ]]; then
        rlRun "mkdir -p -m 0755 $TMPDIR" || return $CKI_UNINITIATED
    fi

    # setup msr tools as package 'msr-tools' is not installed by default
    msr_tools_setup
    if (( $? != 0 )); then
        cki_abort_task "fail to setup msr tools"
    fi

    return $CKI_PASS
}

function cleanup
{
    msr_tools_cleanup
    rlRun "rm -rf $TMPDIR"
    return $CKI_PASS
}

cki_main
exit $?
