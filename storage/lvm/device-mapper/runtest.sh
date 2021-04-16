#!/bin/bash
#
# Copyright (c) 2020-2021 Red Hat, Inc. All rights reserved.
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

source $CDIR/../../include/libstqe.sh
source $CDIR/setup.sh

DMTS_REPO="https://github.com/jthornber/device-mapper-test-suite.git"
DMTS_LOCAL="$CDIR/$(basename $DMTS_REPO | sed 's%.git%%')"

function upload_log_files
{
    typeset log_file=""
    typeset log_files=$(find $LOG_DIR -name "*.log")
    for log_file in $(echo $log_files); do
        cki_upload_log_file $log_file
    done
}

function runtest
{
    # XXX: Never use cki_run_cmd_xxx() wrapper, or it hangs
    source /etc/profile.d/rvm.sh || return 1

    cki_cd $DMTS_LOCAL

    cki_run_cmd_pos "dmtest list --suite thin-provisioning -t BasicTests"
    if (( $? != 0 )); then
        upload_log_files
        return $CKI_FAIL
    fi

    cki_run_cmd_pos "dmtest run --suite thin-provisioning -t BasicTests"
    if (( $? != 0 )); then
        # save what is keeping resources open
        # this can help debug failures like when it is unable to remove a device
        # ex: https://gitlab.com/cki-project/kernel-tests/-/issues/538
        cki_run_cmd_neu "lsof > $LOG_DIR/lsof.log"
        cki_run_cmd_neu "ps -aux > $LOG_DIR/ps_aux.log"
        cki_run_cmd_neu "dmsetup ls > $LOG_DIR/dmsetup_ls.log"
        cki_run_cmd_neu "dmsetup info > $LOG_DIR/dmsetup_info.log"
        upload_log_files
        return $CKI_FAIL
    fi

    cki_pd
    upload_log_files
    return $CKI_PASS
}

function startup
{
    [[ ! -d $TMPDIR ]] && mkdir -p -m 0755 $TMPDIR
    ts_setup || return $?
    return $CKI_PASS
}

function cleanup
{
    cki_run_cmd_neu "rm -rf $TMPDIR"
    return $CKI_PASS
}

cki_main
exit $?
