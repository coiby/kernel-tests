#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/kpatch/stress
#   Description: Kpatch utility stress test
#   Authors: Yulia Kopkova <ykopkova@redhat.com>
#            Chao Ye <cye@redhat.com>
#            Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# TBD:
# 1. Handling of the 5% error rate

#  Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../include/lib.sh

KPATCH_PATCH="${KPATCH_PATCH:-}"
KPATCH_MODULE=""
KPATCH_PATH="${KPATCH_PATH:-}"
STRESSER="${STRESSER:-kbuild trace stress-ng}"
if [ -z "$KPATCH_PATCH" ]; then
    if rpm -qa | grep kpatch-patch ; then
        KPATCH_PATH="/usr/lib/kpatch/$(uname -r)"
        for m in $KPATCH_PATH/*.ko
        do
            if grep -q 'kpatch-' <<< $m ; then
                KPATCH_MODULE=$(echo ${m##*/} | sed -e 's/.ko//')
                break
            fi
        done
    elif is_rhel9; then
        dnf_install_modules_internal
        KPATCH_MODULE="test_klp_livepatch"
        KPATCH_PATH=$(dirname `modinfo --field=filename $KPATCH_MODULE`)
        xz --decompress $KPATCH_PATH/$KPATCH_MODULE.ko.xz
    else
        install_selftests_internal
        rhel10_build_selftests_modules
        KPATCH_MODULE="test_klp_livepatch"
        KPATCH_PATH="${LIVEPATCH_TEST_MODULES}/test_modules"
    fi
else
    KPATCH_MODULE=$(echo ${KPATCH_PATCH} | sed -e "s/kpatch-patch/kpatch/" | sed -e "s/\.test.*/_test/")
fi

echo "KPATCH_MODULE=$KPATCH_MODULE"
echo "KPATCH_PATH=$KPATCH_PATH"

sys_livepatch="/sys/kernel/livepatch"
MOD=${KPATCH_MODULE//-/_}

run_kpatch_in_stress()
{
    local loop_times=500
    local stresser=$1
    local const_loop=$loop_times
    local saved_loop_times=$loop_times
    local failures=0
    local already_loaded=0

    # 2 * nr_cpu kbuild threads.
    sh stress.sh $stresser &
    local _pid=$!

    rlLogInfo "Kpatch load/unload with $stresser stresser"

    while ((loop_times-- > 0)); do
        rlLogInfo "Looping $((const_loop - loop_times)) load/unload"
        if test -f ERROR && rlLogInfo "Error happened in $stresser"; then
            __kpatch_stress_cleanup $_pid
        fi
        rlRun "kpatch load $MOD" 0
        local ret=$?
        if ((already_loaded == 0)) && [ $ret -ne 0 ]; then
            rlPass "hit_load_failure_in_loop$((501 - loop_times))"
            report_activeness_failures
            (( failures++ ))
            (( failures > 25 )) && break
            continue
        fi
        rlRun "kpatch list"
        if ! rlAssertEquals "$MOD should be loaded and installed" 2 $(kpatch list | grep -c $MOD); then
            __kpatch_stress_cleanup $_pid
            break
        fi
        rlRun "kpatch force unload $MOD" 0
        if [ $? -ne 0 ]; then
            rlPass "hit_unload_failure_in_loop$((const_loop - loop_times))"
            report_activeness_failures
            (( unload_failures++ ))
            already_loaded=1
            continue
        fi
        already_loaded=0
        rlRun "kpatch list"
        if ! rlAssertEquals "$MOD should be unloaded and installed" 1 $(kpatch list | grep -c $MOD); then
            __kpatch_stress_cleanup $_pid
            break
        fi
    done

    # We assume 5% failure rate as normal.
    if (( failures > 25 )); then
        rlFail "$saved_loop_times:hit_${failures}_failures"
    else
        rlPass "$saved_loop_times:hit_${failures}_failures"
    fi

    __kpatch_stress_cleanup $_pid
}

__kpatch_stress_cleanup()
{
    local _pid=$1
    __kpatch_stress_subprocess_cleanup $_pid
    rlFileSubmit $reported_failures
    return 0
}

__kpatch_stress_subprocess_cleanup() {
    local _pid=$1
#   kill -stop $_pid
    for subprocess in $(ps -o pid --no-headers --ppid $_pid); do
        __kpatch_stress_subprocess_cleanup "$subprocess"
    done
    kill -15 $_pid
}

reported_failures=activiness.failure

report_activeness_failures()
{
    local f
    local c_new=$(grep 'kpatch: activeness safety check failed' /var/log/messages | wc -l | awk '{print $1}')
    f=$(grep 'kpatch: activeness safety check failed' /var/log/messages | tail -n 1 | awk '{print $NF}')
    echo $f >> $reported_failures
    rlPass "activeness-fail$c_new:$f"
}

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm kpatch
        rlRun "kpatch install $KPATCH_PATH/$KPATCH_MODULE.ko" 0-255
        rlRun "kpatch load $MOD" || rlDie "Cannot load $KPATCH_MODULE"
        rlAssertEquals "Assert $KPATCH_MODULE is enabled" "$(cat $sys_livepatch/$MOD/enabled)" "1" \
        ||  rlDie "Livepatch module $KPATCH_MODULE is not enabled."
        rlRun "kpatch force unload $MOD"
    rlPhaseEnd

    rlPhaseStartTest
        for stresser in ${STRESSER}; do
            run_kpatch_in_stress $stresser
        done
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "kpatch force unload $MOD" 0-255
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
