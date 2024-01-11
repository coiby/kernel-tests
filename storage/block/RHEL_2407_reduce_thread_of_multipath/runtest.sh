#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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

# Include enviroment and libraries
FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../include/include.sh    || exit 1
. /usr/share/beakerlib/beakerlib.sh     || exit 1

function run_test()
{
    rlPass "systemctl status multipathd"

cat <<"EOF" >/etc/multipath.conf
defaults {
        user_friendly_names yes
        find_multipaths no
        enable_foreign "^$"
        dev_loss_tmo    30
}

blacklist_exceptions {
        property "(SCSI_IDENT_|ID_WWN)"
}

blacklist {
}
EOF

    rlRun "systemctl restart multipathd"
    rlPass "systemctl status multipathd"
    rlRun "lsblk"

    [ ! -f thread_num.log ] && touch thread_num.log
    rlRun "ps aux | grep freezable | grep -v grep | wc -l | tee thread_num.log"
    _time=$(date +%Y%m%d-%H%M%S)
    xcnt=0
    while [ ${xcnt} -lt 100 ]
    do
# --------------------------------------------------------------------------------
    rlLog "# multipath -ll &>/dev/null ; sleep 1 ; ps aux | grep freezable | wc -l"
    multipath -ll &> /dev/null
    multipath -ll &> /dev/null
    multipath -ll &> /dev/null
    multipath -ll &> /dev/null
    multipath -ll &> /dev/null
    sleep 1
    rlRun "ps aux | grep freezable | grep -v grep | wc -l | tee thread_num.log"
# --------------------------------------------------------------------------------
    xcnt=$(( ${xcnt} + 1 ))
    done

    for num in `cat thread_num.log`;do
        if [[ ${num} -gt 20 ]]; then
            rlFail "Test failed: the threads not reduce,please check!"
            break
        fi
    done

    rm -rf thread_num.log
    rlRun "mpathconf --disable"
    rlRun "systemctl restart multipathd"
    sleep 3
    rlRun "lsblk"
}

rlJournalStart
    rlPhaseStartTest
        rlRun "uname -a"
        rlLog "$0"
        run_test
        check_log
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
