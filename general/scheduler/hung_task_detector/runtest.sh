#!/bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/hung_task_detector
#   Description: This is a tests for hung_task_detector
#   Author: Chunyu Hu <chuhu@redhat.com>
#
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

. /usr/share/beakerlib/beakerlib.sh ||  exit 1
. ../../../kernel-include/runtest.sh || exit 1

if [ -z "$OUTPUTFILE" ]; then
    export OUTPUTFILE=`mktemp /mnt/testarea/tmp.XXXXXX`
fi

trap 'Cleanup' SIGHUP SIGINT SIGQUIT SIGTERM SIGUSR1

function Cleanup()
{
    true
}
this_arch=$(uname -m)

rlJournalStart
    rlPhaseStartSetup
        rlRun "unset ARCH"

        installer=$(K_GetPkgMgr)
        if [[ ${installer} == "rpm-ostree" ]]; then
            export install_opts="-A -y --idempotent --allow-inactive install"
        else
            export install_opts="-y install"
        fi

        # install kernel-devel for the running kernel version
        devel_pkg=$(K_GetRunningKernelRpmSubPackageNVR devel)

        #Expansion needed
        #shellcheck disable=SC2086
        ${installer} ${install_opts} ${devel_pkg}

        dmesg -c
        pushd kmod_hung || exit 1
        rlRun "make || make EXTRA_CFLAGS=' -D KTIME_OLD_VERSION'" || rlDie "Module failed to be compiled."
        popd || exit 1
        if ! which stress-ng > /dev/null; then
            rlRun "pushd ../../include/scripts/"
            rlRun "sh stress.sh; popd"
        fi
    rlPhaseEnd

    rlPhaseStartTest
        expect_retval=0-255
        [ "$this_arch" = x86_64 ] && expect_retval=0
        old_timeout=$(cat /proc/sys/kernel/hung_task_timeout_secs)
        old_panic=$(cat /proc/sys/kernel/hung_task_panic)
        rlRun "echo 10 > /proc/sys/kernel/hung_task_timeout_secs"
        rlRun "echo 0 > /proc/sys/kernel/hung_task_panic"
        rlRun "dmesg -c" 0-255
        if rlIsRHELLike ">=8"; then
            rpm -q rsyslog > /dev/null || rlRun "${installer} ${install_opts} rsyslog"
            rlRun -l "systemctl status rsyslog | grep running" 0-255 || \
            { rlRun "systemctl enable rsyslog" && rlRun "systemctl start rsyslog"; }
        fi
        rlFileBackup /var/log/messages
        echo > /var/log/messages
        pushd kmod_hung || exit 1

        rlRun "insmod hung.ko runtime=30" 0 "Block for 40 seconds"
        # Wait for 40 seconds
        i=0
        while pgrep 'hung_task-' && ((i < 4)); do
            sleep 10
            ((i++))
        done


        dmesg -C
        rlIsRHELLike ">=8" && journalctl -k --no-hostname > /var/log/messages

        rlRun "tail -n 200 /var/log/messages | grep -i ' blocked for more than'"
        #  on aarch64, this is showned as 'Call trace', but on x86, it's Call Trace.
        rlRun "tail -n 200 /var/log/messages | grep -E 'Call Trace|Call trace' -A 10"
        rlRun "tail -n 200 /var/log/messages | grep -E 'Call Trace|Call trace' -A 10 | grep '\[hung\]'"
        rlRun "dmesg -c" 0-255
        echo > /var/log/messages
        rlLog "start stress-ng for activating stack trace."
        procs=$(( $(nproc) -1 ))
        ((procs)) || procs=1
        stress-ng --vm $procs -t 15 &
        sleep 10
        dmesg -C
        echo > /var/log/messages
        rlRun "echo l > /proc/sysrq-trigger"
        dmesg > dmesg
        if grep -qi 'call trace' dmesg; then
            rlRun "cat dmesg | grep -i 'NMI backtrace for cpu '" $expect_retval
            rlRun "cat dmesg | grep 'Call Trace' -A 10" $expect_retval
            if rlIsRHEL "<=7"; then
                rlRun -l "cat dmesg | egrep '\[<[0-9a-z]*>\] [\?a-z].*'" $expect_retval
            else
                rlRun " cat dmesg | awk 'BEBIN{m=1} / [?a-z_].*\/0x[0-9a-f]+/  && !/NMI/ {print;m=0}END{exit(m)}'" $expect_retval
            fi
        else
            dmesg -C
            rlIsRHELLike ">=8" && journalctl -k --no-hostname > /var/log/messages
            rlRun "tail -n 200 /var/log/messages | grep -i 'NMI backtrace for cpu '" $expect_retval
            rlRun "tail -n 200 /var/log/messages | grep 'Call Trace' -A 10" $expect_retval
            if rlIsRHEL "<=7"; then
                rlRun -l "tail -n 200 /var/log/messages | egrep '\[<[0-9a-z]*>\] [\?a-z].*'" $expect_retval
            else
                rlRun " tail -n 200 /var/log/messages | awk 'BEBIN{m=1} / [?a-z_].*\/0x[0-9a-f]+/  && !/NMI/ {print;m=0}END{exit(m)}'" $expect_retval
            fi
        fi
        rlFileRestore
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "echo $old_timeout > /proc/sys/kernel/hung_task_timeout_secs"
        rlRun "echo $old_panic > /proc/sys/kernel/hung_task_panic"
        # Wait for 40 seconds
        i=0
        while pgrep 'hung_task-' && ((i < 4)); do
            sleep 10
            ((i++))
        done
        rlRun "rmmod hung"
        pkill perf -9
        make clean
        \rm dmesg
        popd || return
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
