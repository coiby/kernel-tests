#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/kpatch/kpatch-dnf
#   Description: Test kpatch-dnf function
#   Author: Zhijun Wang <zhijwang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2022 Red Hat, Inc.
#
#   SPDX-License-Identifier: GPL-2.0-or-later WITH GPL-CC-1.0
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

karch=$(uname -m)
knvr=$(uname -r | sed s/\.$karch//)
kpp=kpatch-patch-$(sed "s/\./_/g" <<< ${knvr%%.el*})
kpp_pkg=${kpp}.${karch}
kpp_module=kpatch_$(sed "s/[\.-]/_/g" <<< ${knvr%%.el*})

config_file="/etc/dnf/plugins/kpatch.conf"

function check_kpatch() {
    command -v kpatch || dnf -y install kpatch kpatch-dnf
}

# shellcheck disable=SC2120 # warning: cleanup_env references arguments, but none are ever passed - it seems false positive
function cleanup_env() {
    load_patch=$(kpatch list | awk "/^Loaded/,/^Installed/ {print $1}" |grep -v "Loaded\|Installed\|^$" | awk '{print $1}')
    install_patch=$(kpatch list | awk "/^Installed/,/*/ {print $1}" |grep -v "Installed\|^$" | awk '{print $1}')

    for i in ${load_patch}; do
        kpatch force unload $i
    done

    for i in ${install_patch}; do
        kpatch uninstall $i
    done

    dnf -qy remove ${kpp_pkg}
}

function dnf_auto() {
    dnf kpatch auto -y
}

function dnf_manual() {
    dnf kpatch manual
}

function dnf_install() {
    dnf kpatch install -y
}

function kpatch_module_check() {
    exp_code=$1
    rlRun "kpatch list"
    rlRun "kpatch list | awk '/^Loaded/,/^Installed/ {print \$1}' | grep ${kpp_module}" ${exp_code}
    rlRun "kpatch list | awk '/^Installed/,/*/ {print \$1}' | grep ${kpp_module}" ${exp_code}
}

function kpatch_status() {
    k_status_exp=$1
    k_status_act=$(dnf kpatch status | grep "Kpatch update setting" | awk -F ":" '{print $2}' | sed "s/\ //g")
    if [ ${k_status_exp} == ${k_status_act} ]; then
        rlLog "The dnf kpatch status is same."
    else
    rlLogWarning "The dnf kpatch status is not matched!"
    fi
}

rlJournalStart
    rlPhaseStartSetup
        check_kpatch
        cleanup_env
    rlPhaseEnd

    rlPhaseStartTest "Set to auto"
        dnf_auto
        kpatch_status auto
        rlAssertGrep True ${config_file}
        rlRun "kpatch list"
        kpatch_module_check 0
        cleanup_env
    rlPhaseEnd

    rlPhaseStartTest "Set to manual"
        dnf_manual
        kpatch_status manual
        rlAssertGrep False ${config_file}
        kpatch_module_check "1-127"
        cleanup_env
    rlPhaseEnd

    rlPhaseStartTest "Set to install"
        dnf_install
        kpatch_status manual
        rlAssertGrep False ${config_file}
        kpatch_module_check 0
        cleanup_env
    rlPhaseEnd

    rlPhaseStartCleanup
        cleanup_env
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
