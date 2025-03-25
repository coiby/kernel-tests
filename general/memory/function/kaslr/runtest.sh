#!/bin/bash
# shellcheck disable=SC2034
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of memory kaslr test
#   Description: TestCaseComment
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
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
# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../../../cki_lib/libcki.sh || exit 1

trap 'rlLog "Rebooting!"; exit' SIGHUP SIGINT SIGQUIT SIGTERM

if stat /run/ostree-booted > /dev/null 2>&1; then
    k_boot="/usr/lib/ostree-boot"
fi
k_boot=${k_boot:-"/boot"}

SLUB_RANDOM=${SLUB_RANDOM:-0}

# First  reboot(up) - compare symbol addr with pre-reboot snapshot
# Seond  reboot(up) - nokaslr in kernel cmdline, snapshot symbol addr
# Third  reboot(up) - compare symbol addr with pre-reboot snapshot
# Fourth reboot(up) - remove nokaslr in cmdline

this_arch=$(uname -m)

# For debug extra reboot code
function fault_injection()
{
    ! test -f INJECTION && touch INJECTION && echo 0 > INJECTION
    local injc=$(cat INJECTION)
    ((injc > 2)) && return

    local fault_list=$(comm  -13 --nocheck-order <(echo -e ${stable_file_list// /"\n"} | sort)  <(echo -e ${cmp_file_list// /"\n"} | sort))
    if [ "$1" = "d" ]; then
        echo "Injecting failure on stable files"
        for f in $stable_file_list; do
            rlLogInfo "$f is injected fault"
            echo ${!f} > ${f}
        done
        echo $((++injc)) > INJECTION
        return
    fi

    if [ "$1" = "c" ]; then
        echo "Injecting failure on cmp files: $fault_list"
        for f in $fault_list; do
            rlLogInfo "$f is injected fault"
            cp ${f} ${f}.old -f
        done
        echo $((++injc)) > INJECTION
        return
    fi

    [ "$1" = r ] || return

    if [ "$(echo $(date +%N) % 4 | bc)" = 0 ]; then
        echo "Injecting failure on stable files"
        for f in $stable_file_list; do
            rlLogInfo "$f is injected fault"
            echo ${!f} > ${f}
        done
    else
        echo "Injecting failure on cmp files: $fault_list"
        for f in $fault_list; do
            rlLogInfo "$f is injected fault"
            cp ${f} ${f}.old -f
        done
    fi
    echo $((++injc)) > INJECTION
}

function get_symbol_addr_snapshot()
{
    case $this_arch in
    x86_64|aarch64|s390x|ppc64le)
        if test -f page_offset_base; then
            for f in $cmp_file_list; do
                mv $f ${f}.old
            done
        fi

        grep -w _text /proc/kallsyms  | awk '{print $1}' > _text
        grep -w page_offset_base /proc/kallsyms  | awk '{print $1}' > page_offset_base
        grep -w vmemmap_base /proc/kallsyms  | awk '{print $1}' > vmemmap_base
        awk '/Kernel code/ {gsub("-.*", "", $1); print $1}' /proc/iomem > Kernel_code
        awk '/Kernel data/ {gsub("-.*", "", $1); print $1}' /proc/iomem > Kernel_data
        awk '/Kernel bss/ {gsub("-.*", "", $1); print $1}' /proc/iomem > Kernel_bss

        #fault_injection ${FAULT:-r}

        for f in $cmp_file_list; do
            echo -e "$f: $(cat $f)"
            test -f ${f}.old && echo -e "${f}.old: $(cat ${f}.old)"
        done

        # make sure we get the _text address
        ! test -s _text && cki_abort_task "failed to get symbol addr"
    ;;
    esac
}

function slub_freelist_random()
{
    [ "$SLUB_RANDOM" -eq 0 ] && echo "Skip ${FUNCNAME[0]}" && return
    uname -r | grep debug && echo "Skip debug kernel" && return
    local kaslr=${1:-0}
    local index=$2
    if ((kaslr)); then
        local t="enabled.$index"
    else
        local t="disabled.$index"
    fi
    pushd slub_random_test
    rlLog "clean dmesg to empty..."
    dmesg -C > /dev/null
    rlRun "insmod slub_random_test.ko"
    rlRun "dmesg > slub_random_test.kaslr.$t"
    rlFileSubmit slub_random_test.kaslr.$t
    rlLog "you need to check slub_random_test.kaslr.$t manually"
    rlRun "rmmod slub_random_test"
    popd
}

function kaslr_phase_prep()
{
    current_state="$(sed -n '1p' TEST_STATE)"
    phase=""
    case "$current_state" in
        before_r_kaslr_snapshot)    phase="kaslr-snapshot";;
        after_r_kaslr_compare)      phase="kaslr-compare";;
        after_r_nokaslr_snapshot)   phase="nokaslr-snapshot";;
        after_r_nokaslr_compare)    phase="nokaslr-compare";;
        after_r_nokaslr_cleanup)    phase="nokaslr-cleanup";;
        before_r_nokaslr_snapshot)  phase="nokaslr-snapshot";;
        after_r_kaslr_snapshot)     phase="kaslr-snapshot";;
        after_r_kaslr_cleanup)      phase="kaslr-cleanup";;
    esac
    echo "debug: current_state=$current_state"
    echo "debug: phase=$phase"
}

function check_x86_paging_level()
{
    if grep -q la57 /proc/cpuinfo 2>/dev/null; then
        echo "Detected la57 cpu support"
        SUPPORT_LA57=1
    fi

    if grep -q no5lvl /proc/cmdline 2>/dev/null; then
        echo "Detected no5lvl kernel parameter"
        SUPPORT_NO5LVL=1
    fi

    if grep -q CONFIG_X86_5LEVEL=y ${k_boot}/config-"$(uname -r)" 2>/dev/null  ; then
        echo "Detected 5lvl config"
        SUPPORT_CONFIG_5LVL=1
    fi
    if [[ $SUPPORT_LA57 -eq 1 &&  $SUPPORT_NO5LVL -eq 0 && $SUPPORT_CONFIG_5LVL -eq 1 ]] ; then
        EXPECT_LVL=5
    else
        EXPECT_LVL=4
    fi
}

function get_default_addr()
{
    if uname -r | grep x86_64 && grep CONFIG_RANDOMIZE_MEMORY=y ${k_boot}/config-"$(uname -r)"; then
        cmp_file_list="_text page_offset_base vmemmap_base Kernel_code Kernel_data Kernel_bss"
    elif uname -r | grep x86_64; then
        cmp_file_list="_text Kernel_code Kernel_data Kernel_bss"
    elif uname -r | grep aarch64; then
        cmp_file_list="_text Kernel_code Kernel_data"
    elif uname -r | grep s390x; then
        cmp_file_list="_text Kernel_code Kernel_data Kernel_bss"
    else
        cmp_file_list="_text"
    fi
    # "drivers/firmware/efi/libstub/x86-stub.c", Kernel_code is determined
    # by efi firmware calls, not consistant for all machines.
    stable_file_list="_text"
    _text=ffffffff81000000
    Kernel_code=01000000

    check_x86_paging_level
    if [ "$EXPECT_LVL" = 5 ]; then
        _text=ffffffff81000000
        Kernel_code=01000000
    fi
}

function arch_kaslr_test()
{

    if [[ ! $phase =~ cleanup ]]; then
        get_symbol_addr_snapshot

        if test -s SETUP_FINISH; then
            local extra_reboots="$(cat SETUP_FINISH)"
        else
            local extra_reboots=0
        fi

        for f in $stable_file_list; do
            if [ "${!f}" = "$(cat ${f})" ] && ((extra_reboots < 3)); then
                rlLogInfo "Default $f: Inserted $extra_reboots extra reboot/compare"
                rlRun "cat TEST_STATE" 0 "Before"
                sed -i '1i'$current_state'' TEST_STATE
                rlRun "cat TEST_STATE" 0 "After"
                echo "$((++extra_reboots))" > SETUP_FINISH
                rlReport "reboot-default-$f-$extra_reboots" PASS
                rstrnt-reboot
                # Make sure the script doesn't continue if rstrnt-reboot get's killed
                # https://github.com/beaker-project/restraint/issues/219
                exit 0
            fi
            rlAssertNotEquals "$f should be non-default" "${!f}" "$(cat $f)"
        done
    fi

    local i=0
    if [ "$current_state" = "after_r_kaslr_compare" ]; then
        rlReport "reboot" PASS
        rlAssertNotGrep nokaslr /proc/cmdline || cki_abort_task "unexpedted test state!"

        if test -s SETUP_FINISH; then
            local extra_reboots="$(cat SETUP_FINISH)"
        else
            local extra_reboots=0
        fi

        ((i++))
        for f in $cmp_file_list; do
            # If two reboots hit the same address value, do an extra reboot, 3 extra reboots at most
            if [ "$(diff ${f}.old ${f} | wc -l)" = "0" ] && ((extra_reboots < 3)); then
                rlLogInfo "$f: Inserted $extra_reboots extra reboot/compare"
                rlRun "cat TEST_STATE" 0 "Before"
                sed -i '1iafter_r_kaslr_compare' TEST_STATE
                rlRun "cat TEST_STATE" 0 "After"
                echo "$((++extra_reboots))" > SETUP_FINISH
                rlReport "reboot-same-$f-$extra_reboots" PASS
                rstrnt-reboot
                # Make sure the script doesn't continue if rstrnt-reboot get's killed
                # https://github.com/beaker-project/restraint/issues/219
                exit 0
            fi
            rlAssertNotEquals "$f should be changed" "$(cat ${f}.old)" "$(cat $f)"
        done
        slub_freelist_random 1 $i
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rlRun "rpm-ostree kargs --append-if-missing=nokaslr --import-proc-cmdline" 0
        else
            rlRun "grubby --args nokaslr --update-kernel ALL" 0
            [ "$this_arch" = "s390x" ] && zipl
        fi
        rlPhaseEnd
        rstrnt-reboot
        # Make sure the script doesn't continue if rstrnt-reboot get's killed
        # https://github.com/beaker-project/restraint/issues/219
        exit 0
    elif [ "$current_state" = "after_r_kaslr_cleanup" ]; then
        rlAssertGrep nokaslr /proc/cmdline || cki_abort_task "unexpedted test state!"
    elif [ "$current_state" = "after_r_kaslr_snapshot" ]; then
        rlReport "reboot" PASS
        rlAssertNotGrep nokaslr /proc/cmdline || cki_abort_task "unexpedted test state!"
        rlPhaseEnd
        rstrnt-reboot
        # Make sure the script doesn't continue if rstrnt-reboot get's killed
        # https://github.com/beaker-project/restraint/issues/219
        exit 0
    else
        rlAssertNotGrep nokaslr /proc/cmdline || cki_abort_task "unexpedted test state!"
        slub_freelist_random 1 $i
        rlPhaseEnd
        rstrnt-reboot
        # Make sure the script doesn't continue if rstrnt-reboot get's killed
        # https://github.com/beaker-project/restraint/issues/219
        exit 0
    fi
}

function verify_symbol_default_addr()
{
    case $this_arch in
        x86_64)
            for f in $stable_file_list; do
                rlAssertEquals "$f should be default" "${!f}" "$(cat $f)"
            done
            ;;
        *)
            true
            ;;
    esac
}

function arch_nokaslr_test()
{
    if [ "$current_state" = "after_r_nokaslr_snapshot" ]; then
            rlReport "reboot" PASS
    fi

    if [[ ! $phase =~ cleanup ]]; then
        get_symbol_addr_snapshot
        verify_symbol_default_addr
    fi

    local i=0
    if [ "$current_state" = "after_r_nokaslr_compare" ]; then
        rlReport "reboot" PASS
        rlAssertGrep nokaslr /proc/cmdline
        ((i++))
        for f in $cmp_file_list; do
            rlAssertEquals "$f should be same" "$(cat ${f}.old)" "$(cat $f)"
        done
        slub_freelist_random 0 $i
        if stat /run/ostree-booted > /dev/null 2>&1; then
            rlRun "rpm-ostree kargs --delete-if-present=nokaslr --import-proc-cmdline" 0
        else
            rlRun "grubby --remove-args nokaslr --update-kernel ALL"
            [ "$this_arch" = "s390x" ] && zipl
        fi
        rlPhaseEnd
        rstrnt-reboot
    elif [ "$current_state" = "after_r_nokaslr_cleanup" ]; then
        rlReport "reboot" PASS
        rlAssertNotGrep nokaslr /proc/cmdline
    elif [ "$current_state" = "before_r_nokaslr_snapshot" ]; then
        rlAssertGrep nokaslr /proc/cmdline
        rlPhaseEnd
        rstrnt-reboot
    else
        rlAssertGrep nokaslr /proc/cmdline
        slub_freelist_random 0 $i
        rlPhaseEnd
        rstrnt-reboot
    fi
}

function run_kaslr()
{
    if [ -e ${k_boot}/config-"$(uname -r)" ]; then
        grep CONFIG_RANDOMIZE_BASE=y ${k_boot}/config-"$(uname -r)" || { rlReport "Skip-not-support" PASS; return; }
    elif [ -e /proc/config.gz ]; then
        zcat /proc/config.gz | grep CONFIG_RANDOMIZE_BASE=y || { rlReport "Skip-not-support" PASS; return; }
    else
        rlReport "Skip-not-support" PASS;
        return;
    fi

    get_kernel_version
    if  [ "$kver_major" -lt 3 ]; then
        rlReport "Skip-not-support" PASS
        return
    elif [ "$kver_major" -eq 3 ] && [ "$kver_minor" -eq 10 ]; then
        if [ "$krel_major" -lt 705 ]; then
            rlReport "Skip-not-support" PASS
            return
        fi
    fi
    rlPhaseStartTest $phase
        rlRun "sed -i '1d' TEST_STATE" 0 "to next state $(sed -n '2p' TEST_STATE)"
        case "$phase" in
        kaslr*)
            arch_kaslr_test
            ;;
        nokaslr*)
            arch_nokaslr_test
            ;;
        esac

    rlPhaseEnd
}

function prepare_state_q()
{
    touch TEST_STATE
    if grep nokaslr /proc/cmdline; then
        echo "default cmdline: $(cat /proc/cmdline)"
        echo "before_r_nokaslr_snapshot" > TEST_STATE
        echo "after_r_nokaslr_compare" >> TEST_STATE
        echo "after_r_kaslr_snapshot" >> TEST_STATE
        echo "after_r_kaslr_compare" >> TEST_STATE
        echo "after_r_kaslr_cleanup" >> TEST_STATE
    else
        echo "before_r_kaslr_snapshot" > TEST_STATE
        echo "after_r_kaslr_compare" >> TEST_STATE
        echo "after_r_nokaslr_snapshot" >> TEST_STATE
        echo "after_r_nokaslr_compare" >> TEST_STATE
        echo "after_r_nokaslr_cleanup" >> TEST_STATE
    fi
    rlRun -l "cat TEST_STATE" 0 "states we are goting to handle."
}

function get_kernel_version()
{
    kver_major=$(uname -r | cut -d- -f1 | cut -d. -f 1) # 3
    kver_minor=$(uname -r | cut -d- -f1 | cut -d. -f 2) # 10
    kver_mminor=$(uname -r | cut -d- -f1 | cut -d. -f 3) # 0
    krel_major=$(uname -r | cut -d- -f2 | cut -d. -f 1) # 514
}

function select_yum_tool()
{
    if [ -x /usr/bin/dnf ]; then
        YUM=/usr/bin/dnf
        ${YUM} install -y dnf-plugins-core
    elif [ -x /usr/bin/yum ]; then
        YUM=/usr/bin/yum
        ${YUM} install -y yum-plugin-copr
    elif stat /run/ostree-booted > /dev/null 2>&1; then
        YUM="rpm-ostree -A --idempotent --allow-inactive"
        ${YUM} install -y dnf-plugins-core
    else
        rstrnt-report-result ${TEST} WARN 99
        cki_abort_task "No tool to download kernel from a repo" | tee -a ${OUTPUTFILE}
    fi
}

k_name=$(rpm --queryformat '%{name}\n' -qf /boot/config-$(uname -r) | sed -e 's/-core//')
rlJournalStart
    if ! test -f SETUP_FINISH; then
        rlPhaseStartSetup
            if journalctl -kb | grep -i 'kaslr disabled due to lack of seed'; then
                rlLog "kaslr is disabled because of no EFI_RNG_PROTOCOL available, skip test"
                rstrnt-report-result "${TEST}" SKIP
                exit 0
            fi
            select_yum_tool
            prepare_state_q
            grep nokaslr /proc/cmdline && rlLogInfo "nokaslr in cmdline: $(cat /proc/cmdline)"
            unset ARCH
            if [ "$SLUB_RANDOM" -ne 0 ]; then
                uname -r | grep debug && { rpm -q ${k_name}-devel-debug || ${YUM} -y install ${k_name}-devel-debug-$(uname -r); }
                # slub freelist random testing
                ${YUM} -y install libelf-dev || ${YUM} -y install libelf-devel || ${YUM} -y install elfutils-libelf-devel
                rpm -q ${k_name}-devel | grep $(uname -r) || ${YUM} -y install ${k_name}-devel-$(uname -r)
                pushd slub_random_test
                rlRun "make" 0 "Compile slub random test kernel test module"
                popd
            fi
            touch SETUP_FINISH
        rlPhaseEnd
    fi

    case $this_arch in
        x86_64|aarch64|s390x|ppc64le)
            kaslr_phase_prep
            get_default_addr
            run_kaslr
            ;;
        *)
            rlPhaseStartTest "SKIP"
            rlPhaseEnd
            ;;
    esac

    rlPhaseStartCleanup
        rlRun "rm TEST_STATE SETUP_FINISH -f"
        #test -f INJECTION && rlRun "rm INJECTION -f"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
