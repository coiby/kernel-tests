#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
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

rlJournalStart
    rlPhaseStartSetup
        rlShowRunningKernel
        case `uname -m` in
            "x86_64")
                ;;
            *)
                echo "[SKIP] only support x86_64 on RHEL8.5+ atm, details in bug 1901039"
                rstrnt-report-result $RSTRNT_TASKNAME SKIP
                exit 0 ;;
        esac
        knvr="$(uname -r)"
        if [ -e /run/ostree-booted ]; then
            kconfig="/usr/lib/ostree-boot/config-$knvr"
            rlRun "rpm-ostree -A --idempotent --allow-inactive install kernel-automative-selftests-internal"
        else
            kconfig="/boot/config-$knvr"
            if [[ $knvr =~ rt ]]; then
                kernelVar="kernel-rt"
            else
                kernelVar="kernel"
            fi
            rlRun "yum install -y --skip-broken $kernelVar-selftests-internal-${knvr%.*}"
        fi
    rlPhaseEnd

    rlPhaseStartTest "check config"
        rlRun "grep LSM $kconfig"
        rlRun "grep 'CONFIG_BPF_LSM=y' $kconfig"
        rlRun "grep 'CONFIG_LSM' $kconfig | grep bpf"
    rlPhaseEnd

    rlPhaseStartTest "kselftest"
        rlRun "/usr/libexec/kselftests/bpf/test_progs -t test_lsm | tee output.txt"
        rlRun "grep '0 SKIPPED' output.txt"
        rlRun "grep '0 FAILED' output.txt"
        rlFileSubmit output.txt
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f output.txt"
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
