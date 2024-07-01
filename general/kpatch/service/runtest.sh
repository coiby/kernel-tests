#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/kpatch/service
#   Description: Kpatch utility service tests
#   Author: Yulia Kopkova <ykopkova@redhat.com>
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

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../include/lib.sh

MOD="test_klp_livepatch"

if is_rhel9; then
    dnf_install_modules_internal
    MOD_PATH=$(dirname `modinfo --field=filename $MOD`)
    xz --decompress $MOD_PATH/$MOD.ko.xz
else
    install_selftests_internal
    rhel10_build_selftests_modules
    MOD_PATH="${LIVEPATCH_TEST_MODULES}/test_modules"
fi

echo "MOD=$MOD"
echo "MOD_PATH=$MOD_PATH"

sys_livepatch="/sys/kernel/livepatch"

KPATCH_VER=$(rpm -q --queryformat "%{VERSION}%{RELEASE}\n"  kpatch | awk -F "." '{print $1$2$3}' | tr -cd '[0-9]')
[ $KPATCH_VER -ge 0925 ] && CHKDIR_FLAG=1

# Following function fixed in bz1930108 on rhel8
CLEAN_KPATCH_DIR()
{
    rlRun "ls -1 /var/lib/kpatch | grep -qE \".*\"" 1 "Verify /var/lib/kpatch is empty"
}

CREATE_KPATCH_DIR()
{
    rlRun "test -d /var/lib/kpatch" 0 "Verify /var/lib/kpatch was created"
    rlRun "test -d /var/lib/kpatch/$(uname -r)" 0 "Verify /var/lib/kpatch/$(uname -r) was created"
}


rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm $PACKAGE
        rlRun "kpatch force unload --all"
        if ! kpatch list | grep $MOD; then
            rlRun "kpatch install $MOD_PATH/$MOD.ko" || rlDie "Can't install $MOD_PATH/$MOD"
            kpatch_install=1
            [ x$CHKDIR_FLAG == x1 ] && CREATE_KPATCH_DIR
        fi
    rlRun "kpatch load $MOD" || rlDie "Cannot load $KPATCH_MODULE"
    rlAssertEquals "Assert $MOD is enabled" "$(cat $sys_livepatch/$MOD/enabled)" "1" \
        ||  rlDie "Livepatch module $MOD is not enabled."
        rlRun "kpatch list | grep -E \"$MOD.*enabled\""
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "kpatch info $MOD | grep -E \"livepatch:.*Y\""
        rlAssertEquals "$MOD should be installed and loaded" 2 $(kpatch list | grep -c $MOD)
        rlRun "kpatch uninstall $MOD"
        rlRun "kpatch list"
        [ x$CHKDIR_FLAG == x1 ] && CLEAN_KPATCH_DIR
        rlAssertEquals "$MOD should be loaded and uninstalled" 1 $(kpatch list | grep -c $MOD)
        rlRun "kpatch force unload $MOD"
        rlRun "kpatch list"
        rlAssertEquals "$MOD should be unloaded and uninstalled" 0 $(kpatch list | grep -c $MOD)
        rlRun "kpatch install $MOD_PATH/$MOD.ko"
        rlRun "kpatch list"
        [ x$CHKDIR_FLAG == x1 ] && CREATE_KPATCH_DIR
        rlAssertEquals "$MOD should be unloaded and installed" 1 $(kpatch list | grep -c $MOD)
        rlRun "kpatch load $MOD"
        rlRun "kpatch list"
        rlAssertEquals "$MOD should be loaded and installed" 2 $(kpatch list | grep -c $MOD)
        rlRun "kpatch force unload $MOD"
        rlRun "kpatch list"
        rlAssertEquals "$MOD should be unloaded and installed" 1 $(kpatch list | grep -c $MOD)

        rlRun -l "kpatch version"
        rlAssertEquals "kpatch version matches rpm" $(kpatch version) "$(rpm -q $PACKAGE | cut -f2 -d'-')"

        rlRun -l "kpatch" 1
        rlRun "kpatch 2>&1 | grep usage"

        rlRun "systemctl start $SERVICE"
        rlRun "kpatch list | grep -E \"$MOD.*enabled\""
        rlRun "systemctl restart $SERVICE"
        rlRun "kpatch list | grep -E \"$MOD.*enabled\""
        rlRun "systemctl stop $SERVICE"
        rlRun "kpatch list | grep -E \"$MOD.*enabled\""
    rlPhaseEnd

    rlPhaseStartCleanup
        [[ ! -z $kpatch_install ]] && rlRun "kpatch force unload $MOD; kpatch uninstall $MOD"
        [ x$CHKDIR_FLAG == x1 ] && CLEAN_KPATCH_DIR
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
