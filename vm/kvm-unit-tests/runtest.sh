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

# shellcheck source=../../cki_lib/libcki.sh
. ../../cki_lib/libcki.sh || exit 1

BINDIR=./tests
LOGDIR=./logs
GICVERSION=""
MACHINES=("pc")
CPUTYPE=""
OSVERSION=""
KVMPARAMFILE=/etc/modprobe.d/kvm-ci.conf
REPOS=("default")
SETUPS=("setupDF")
CLEANUPS=("cleanupDF")
ACCELS=()
MINOR=$(grep '^VERSION_ID' /etc/os-release | awk -F'=' ' gsub(/"/,"") { print $2}' | awk -F. '{print $2}')
UPSTREAM=NO
NODISABLE=NO

source /usr/share/beakerlib/beakerlib.sh

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  # shellcheck disable=SC2221,SC2222
  case $1 in
    -u|--upstream)
      UPSTREAM=YES
      shift # past argument
      ;;
    -n|--nodisable)
      NODISABLE=YES
      shift # past argument
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]}"

#
# A simple wrapper function to skip a test because beakerlib doesn't support
# such an important feature, right here we just leverage 'beaker'. Note we
# don't call function report_result() as it directly invoke command
# rstrnt-report-result actually
#
function rlSkip
{
    . ../../cki_lib/libcki.sh || exit 1

    rlLog "Skipping test because $*"
    rstrnt-report-result "${RSTRNT_TASKNAME}" SKIP

    #
    # As we want result="Skip" status="Completed" for all scenarios, right here
    # we always exit 0, otherwise the test will skip/abort
    #
    exit 0
}

function checkPlatformSupport
{
    typeset hwpf=${1?"*** what hardware-platform?, e.g. x86_64"}
    [[ $hwpf == "x86_64" ]] && return 0
    [[ $hwpf == "aarch64" ]] && return 0
    [[ $hwpf == "ppc64" ]] && return 0
    [[ $hwpf == "ppc64le" ]] && return 0
    [[ $hwpf == "s390x" ]] && return 0
    return 1
}

function checkVirtSupport
{
    typeset hwpf=${1?"*** what hardware-platform?, e.g. x86_64"}

    if [[ $OSVERSION == "RHEL8" ]] && [[ $MINOR -lt 6 ]] && dnf repolist --all | grep -q rhel8-advvirt; then
        REPOS+=("rhel8-advvirt")
        SETUPS+=("setupAV")
        CLEANUPS+=("cleanupAV")
    fi

    if [[ $OSVERSION == "RHEL9" ]] && dnf repolist --all | grep -q virt-weeklyrebase; then
        REPOS+=("virt-weeklyrebase")
        SETUPS+=("setupWR")
        CLEANUPS+=("cleanupWR")
    fi

    if [[ $hwpf == "x86_64" ]]; then
        ACCELS+=("kvm")
        if [[ $OSVERSION == "RHEL9" || $OSVERSION == "CENTOS_STREAM_9" ]]; then
            MACHINES=("q35")
        else
            MACHINES+=("q35")
        fi
        if (grep -q 'vmx' /proc/cpuinfo); then
            CPUTYPE="INTEL"
        elif (grep -q 'svm' /proc/cpuinfo); then
            CPUTYPE="AMD"
        fi
        grep -qE '(vmx|svm)' /proc/cpuinfo
        return $?
    elif [[ $hwpf == "aarch64" ]]; then
        ACCELS+=("kvm")
        if journalctl -k | grep -qi "disabling GICv2" ; then
            GICVERSION="3"
        else
            GICVERSION="2"
        fi
        CPUTYPE="ARMGICv$GICVERSION"
        journalctl -k | grep -iqE "kvm.*: (Hyp|VHE) mode initialized successfully"
        return $?
    elif [[ $hwpf == "ppc64" || $hwpf == "ppc64le" ]]; then
        ACCELS+=("kvm,cap-ccf-assist=off")
        ACCELS+=("tcg")
        if (grep -q 'POWER9' /proc/cpuinfo); then
            CPUTYPE="POWER9"
        else
            CPUTYPE="POWER8"
        fi
        grep -qE 'platform.*PowerNV' /proc/cpuinfo
        return $?
    elif [[ $hwpf == "s390x" ]]; then
        ACCELS+=("kvm")
        if (grep -q 'machine = 2964' /proc/cpuinfo); then
            CPUTYPE="z13"
        elif (grep -q 'machine = 3907' /proc/cpuinfo); then
            CPUTYPE="z14"
        elif (grep -q 'machine = 8561' /proc/cpuinfo); then
            CPUTYPE="z15"
        else
           CPUTYPE="S390X"
        fi
        grep -qE 'features.*sie' /proc/cpuinfo
        return $?
    else
        return 1
    fi
}

function getTests
{
    # List of tests to run on all architectures
    ALL_TESTS=()
    while IFS=  read -r -d $'\0'; do
        ALL_TESTS+=("$REPLY")
    done < <(find $BINDIR/ -maxdepth 1 -type f -executable -printf "%f\0")
}

function disableTest
{
    mapfile -d $'\0' -t ALL_TESTS < <(printf '%s\0' "${ALL_TESTS[@]}" | grep -Pzwv "$1")
}

function disableTests
{
    typeset hwpf
    hwpf=$(uname -m)

    # Disable tests for RHEL8 Kernel (4.18.X)
    if [[ $OSVERSION == "RHEL8" ]]; then
        # Disabled x86_64 tests for Intel & AMD machines
        if [[ $hwpf == "x86_64" ]]; then
            if [[ $KUT_MACHINE == "pc" ]]; then
                # Disable test hyperv_synic, hyperv_connections, hyperv_stimer
                # due to https://bugzilla.redhat.com/show_bug.cgi?id=1668573
                disableTest "hyperv_synic"
                disableTest "hyperv_connections"
                disableTest "hyperv_stimer"
            fi
            if [[ $CPUTYPE == "AMD" ]]; then
                disableTest "svm"
                disableTest "msr"
                disableTest "svm_npt"
                disableTest "emulator"
            fi
            if [[ $CPUTYPE == "INTEL" ]]; then
                disableTest "emulator"
                disableTest "msr"
                disableTest "pmu"
                disableTest "vmx"
                disableTest "vmx_pf_exception_test_fep"
            fi
        fi
        if [[ $hwpf == "aarch64" ]]; then
            disableTest "pmu-chained-counters"
            disableTest "pmu-chained-sw-incr"
            disableTest "pmu-chain-promotion"
            disableTest "pmu-overflow-interrupt"
        fi
        if [[ $hwpf == "ppc64" || $hwpf == "ppc64le" ]]; then
            disableTest "spapr_vpa"
        fi
    fi

    # Disable tests for RHEL9 Kernel (5.14.X)
    if [[ $OSVERSION == "RHEL9" ]]; then
        # Disabled x86_64 tests for Intel & AMD machines
        if [[ $hwpf == "x86_64" ]]; then
            if [[ $CPUTYPE == "AMD" ]]; then
                disableTest "svm"
                disableTest "svm_npt"
            fi
            if [[ $CPUTYPE == "INTEL" ]]; then
                disableTest "pmu"
                disableTest "vmx"
                disableTest "vmx_pf_exception_test_fep"
            fi
        fi
    fi

    # Disable tests for CentOS stream 9 Kernel
    if [[ $OSVERSION == "CENTOS_STREAM_9" ]]; then
        # Disabled x86_64 tests for Intel & AMD machines
        if [[ $hwpf == "x86_64" ]]; then
            if [[ $CPUTYPE == "AMD" ]]; then
                disableTest "svm"
                disableTest "svm_npt"
            fi
            if [[ $CPUTYPE == "INTEL" ]]; then
                disableTest "pmu"
                disableTest "vmx"
                disableTest "vmx_pf_exception_test_fep"
            fi
        fi
    fi

    # Disable this test on Upstream testing (5.18.X)
    if [[ $OSVERSION == "ARK" || $OSVERSION == "UPSTREAM" ]]; then
        if [[ $hwpf == "x86_64" ]]; then
            disableTest "apic-split"
            disableTest "apic"
            disableTest "xsave"
            if [[ $CPUTYPE == "INTEL" ]]; then
                disableTest "vmx"
            fi
            if [[ $CPUTYPE == "AMD" ]]; then
                disableTest "svm"
            fi
        fi
    fi
}

function setupRepo
{
    # clone the kvm-unit-tests repo
    rlRun "rm -rf kvm-unit-tests"
    if [[ "${UPSTREAM}" == "YES" ]] ; then
      rlRun "git clone --depth=1 --branch=upstream https://gitlab.com/multi-arch-ci/kvm-unit-tests.git > /dev/null 2>&1"
    else
      rlRun "git clone --depth=1 --branch=master https://gitlab.com/multi-arch-ci/kvm-unit-tests.git > /dev/null 2>&1"
    fi
    rlRun "cd kvm-unit-tests > /dev/null 2>&1"

    if [[ $hwpf == "ppc64" || $hwpf == "ppc64le" ]]; then
        rlRun "./configure --endian=little"
    else
        rlRun "./configure --arch=$hwpf"
    fi
}

function setup
{
    rlPhaseStartSetup
    rlRun "pushd '.'"

    if grep -q "Red Hat Enterprise Linux release 8." /etc/redhat-release; then
        OSVERSION="RHEL8"
    elif grep -q "Red Hat Enterprise Linux release 9." /etc/redhat-release; then
        OSVERSION="RHEL9"
    elif grep -q "CentOS Stream release 9" /etc/redhat-release; then
        OSVERSION="CENTOS_STREAM_9"
    elif [ -n "$CKI_SELFTESTS_URL" ]; then
        OSVERSION="UPSTREAM"
    else
        OSVERSION="ARK"
    fi

    # tests are currently supported on x86_64, aarch64, ppc64 and s390x
    hwpf=$(uname -m)
    if checkPlatformSupport "$hwpf"; then
        # test can only run on hardware that supports virtualization
        rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running on supported arch"
        if checkVirtSupport "$hwpf"; then
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Hardware supports virtualization, proceeding"
        else
            rlSkip "[$OSVERSION][$hwpf][$CPUTYPE] CPU doesn't support virtualization"
        fi
    else
        rlSkip "[$OSVERSION][$hwpf] test is only supported on x86_64, aarch64, ppc64 or s390x"
    fi

    # test should only run on a system with 1 or more cpus
    typeset cpus
    cpus=$(grep -cE ^processor /proc/cpuinfo)
    if (( cpus > 1 )); then
        rlLog "[$OSVERSION][$hwpf][$CPUTYPE] You have sufficient CPU's to run the test"
    else
        rlSkip "[$OSVERSION][$hwpf][$CPUTYPE] system requires > 1 CPU"
    fi

    rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running tests for OSVERSION: $OSVERSION"
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running tests for ARCH: $hwpf"
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running tests for CPUTYPE: $CPUTYPE"
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running tests for MACHINES: ${MACHINES[*]}"
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running tests for REPOS: ${REPOS[*]}"
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE] Running tests for KERNEL: $(uname -a)"

    KVM_SYSFS=/sys/module/kvm/parameters/
    KVM_OPTIONS=""
    if [[ $hwpf == "x86_64" ]]; then
        KVM_OPTIONS+=("enable_vmware_backdoor")
        KVM_OPTIONS+=("force_emulation_prefix")
    elif [[ $hwpf == "s390x" ]]; then
        KVM_OPTIONS+=("nested")
    fi

    KVM_ARCH=""
    KVM_MODULES=()
    KVM_ARCH_OPTIONS=()
    if [[ $CPUTYPE == "INTEL" ]]; then
        KVM_ARCH="kvm_intel"
        KVM_ARCH_OPTIONS+=("nested")
    elif [[ $CPUTYPE == "AMD" ]]; then
        KVM_ARCH="kvm_amd"
        KVM_ARCH_OPTIONS+=("nested")
    elif [[ $hwpf == "ppc64" || $hwpf == "ppc64le" ]]; then
        KVM_ARCH="kvm_hv"
        KVM_MODULES+=("kvm_pr")
        KVM_ARCH_OPTIONS+=("nested")
    fi
    KVM_MODULES+=("$KVM_ARCH")
    KVM_MODULES+=("kvm")
    KVM_ARCH_SYSFS=/sys/module/$KVM_ARCH/parameters/

    # Set the KVM parameters needed for the tests
    : > $KVMPARAMFILE
    for opt in "${KVM_OPTIONS[@]}"; do
        echo -e "options kvm $opt=1\n" >> $KVMPARAMFILE
    done
    for opt in "${KVM_ARCH_OPTIONS[@]}"; do
        echo -e "options $KVM_ARCH $opt=1\n" >> $KVMPARAMFILE
    done

    # Export env variables used by KVM Unit Tests
    export TIMEOUT=3000s

    # Reload the modules
    for mod in "${KVM_MODULES[@]}"; do rmmod -f "$mod" > /dev/null 2>&1; done
    modprobe -a kvm $KVM_ARCH

    # Test if the KVM parameters were set correctly
    for opt in "${KVM_OPTIONS[@]}"; do
        if ! grep -q "Y|y|1" "$KVM_SYSFS/$opt"; then
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE][WARNING] kvm module option $opt not set"
        else
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE] kvm module option $opt is set"
        fi
    done
    for opt in "${KVM_ARCH_OPTIONS[@]}"; do
        if ! grep -q "Y|y|1" "$KVM_ARCH_SYSFS/$opt"; then
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE][WARNING] $KVM_ARCH module option $opt not set"
        else
            rlLog "[$OSVERSION][$hwpf][$CPUTYPE] $KVM_ARCH module option $opt is set"
        fi
    done

    # set the qemu-kvm path
    if [ -e /usr/libexec/qemu-kvm ]; then
        export QEMU="/usr/libexec/qemu-kvm"
    elif [ -e /usr/bin/qemu-kvm ]; then
        export QEMU="/usr/bin/qemu-kvm"
    fi

    if [ -z "$QEMU" ]; then
        rlSkip "[$OSVERSION][$hwpf][$CPUTYPE] Can't find qemu binary"
    fi

    # if running on rhel8, use python3
    if [[ $OSVERSION == "RHEL8" ]] && [ ! -f /usr/bin/python ]; then
        ln -s /usr/libexec/platform-python /usr/bin/python
    fi

    # enable nmi_watchdog since some unit tests depend on this
    if test -f "/proc/sys/kernel/nmi_watchdog"; then
        echo 0 > /proc/sys/kernel/nmi_watchdog
    fi

    setupRepo

    rlRun "popd"
    rlPhaseEnd
}

# shellcheck disable=SC2317
function setupDF
{
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE][$mach][$repo] Installing qemu-kvm version from given repository"
    dnf module -y reset virt > /dev/null 2>&1
    dnf module -y enable virt > /dev/null 2>&1
    dnf install -y qemu-kvm > /dev/null 2>&1
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE][$mach][$repo] QEMU version installed: `rpm -q qemu-kvm`"
}

# shellcheck disable=SC2317
function cleanupDF
{
    return
}

# shellcheck disable=SC2317
function setupAV
{
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE][$mach][$repo] Installing qemu-kvm version from given repository"
    dnf remove -y qemu-* > /dev/null 2>&1
    dnf module -y reset virt > /dev/null 2>&1
    dnf module -y --enablerepo=rhel8-advvirt enable virt:av  > /dev/null 2>&1
    dnf install -y --enablerepo=rhel8-advvirt qemu-kvm > /dev/null 2>&1
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE][$mach][$repo] QEMU version installed: `rpm -q qemu-kvm`"
}

# shellcheck disable=SC2317
function cleanupAV
{
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE][$mach][$repo] Removing qemu-kvm version installed from repository"
    dnf remove -y qemu-* > /dev/null 2>&1
    dnf module -y reset virt > /dev/null 2>&1
    dnf module -y enable virt > /dev/null 2>&1
}

# shellcheck disable=SC2317
function setupWR
{
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE][$mach][$repo] Installing qemu-kvm version from given repository"
    dnf remove -y qemu-* > /dev/null 2>&1
    dnf module -y reset virt > /dev/null 2>&1
    dnf module -y disable virt > /dev/null 2>&1
    dnf install -y --enablerepo=virt-weeklyrebase qemu-kvm > /dev/null 2>&1
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE][$mach][$repo] QEMU version installed: `rpm -q qemu-kvm`"
}

# shellcheck disable=SC2317
function cleanupWR
{
    rlLog "[$OSVERSION][$hwpf][$CPUTYPE][$mach][$repo] Removing qemu-kvm version installed from repository"
    dnf remove -y qemu-* > /dev/null 2>&1
    dnf module -y reset virt > /dev/null 2>&1
    dnf module -y enable virt > /dev/null 2>&1
}

function runtest
{
    rlPhaseStartTest prepare
    rlRun "pushd '.'"

    rlRun "cd kvm-unit-tests"

    rm -rf $LOGDIR
    mkdir $LOGDIR
    rlPhaseEnd

    i=0
    for repo in "${REPOS[@]}"; do
        ${SETUPS[$i]}

        for mach in "${MACHINES[@]}"; do
            export KUT_MACHINE=$mach

            j=0
            for accel in "${ACCELS[@]}"; do
                rlPhaseStartTest "prepare-${mach}-${repo}-${accel}"
                export ACCEL=$accel
                make clean > /dev/null 2>&1
                rlRun "make standalone > /dev/null 2>&1"
                # Prepare lists of tests to run
                getTests
                if [[ "${NODISABLE}" == "NO" ]] ; then
                    disableTests
                fi
                rlLog "[$OSVERSION][$hwpf][$CPUTYPE][$mach][$repo][$accel] Running tests for ACCEL: $accel"
                rlPhaseEnd
                # Run tests
                for test in "${ALL_TESTS[@]}"; do
                    rlPhaseStartTest "${mach}-${repo}-${accel}-${test}"
                    rlRun "yes | $BINDIR/$test > $LOGDIR/${j}_${mach}_${repo}_${accel}_$test.log 2>&1" 0,2,77
                    rlPhaseEnd
                done
                j=$((j+1))
            done

            ${CLEANUPS[$i]}
        done
        i=$((i+1))
    done

    rlPhaseStartTest completed
    cd $LOGDIR || return
    logs=$(ls *.log)
    for log in $logs; do rlFileSubmit "$log" ; done

    rlRun "popd"
    rlPhaseEnd
}

function cleanup
{
    rlPhaseStartCleanup
    rlRun "pushd '.'"

    dnf remove -y qemu-* > /dev/null 2>&1
    dnf module -y reset virt > /dev/null 2>&1
    dnf module -y enable virt > /dev/null 2>&1
    dnf install -y qemu-kvm > /dev/null 2>&1

    rlRun "popd"
    rlPhaseEnd
}

function main
{
    rlJournalStart

    setup
    runtest
    cleanup

    rlJournalEnd
}

main
exit $?
