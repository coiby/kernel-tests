#!/bin/bash
#
# Copyright (c) 2019-2021 Red Hat, Inc. All rights reserved.
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

source $(dirname $(readlink -f $BASH_SOURCE))/../../cki_lib/libcki.sh

STQE_GIT="https://gitlab.com/rh-kernel-stqe/python-stqe.git"
STQE_STABLE_VERSION=${STQE_STABLE_VERSION:-"stable"}
LIBSAN_STABLE_VERSION=${LIBSAN_STABLE_VERSION:-"0.3.0"}

function stqe_get_fwroot
{
    typeset fwroot="/var/tmp/$(basename $STQE_GIT | sed 's/.git//')"
    echo $fwroot
}

function stqe_init_fwroot
{
    typeset fwbranch=$1

    # clone the framework
    typeset fwroot=$(stqe_get_fwroot)
    cki_run_cmd_neu "rm -rf $fwroot"
    cki_run_cmd_pos "git clone $STQE_GIT $fwroot" || \
        cki_abort_task "fail to clone $STQE_GIT"

    # install the framework
    cki_cd $fwroot

    typeset python="python3"
    typeset pkg_mgr=$(dnf > /dev/null 2>&1 && echo dnf || echo yum)
    if ! $python -V > /dev/null 2>&1; then
        cki_run_cmd_neu "$pkg_mgr install -y python3" || \
            cki_run_cmd_neu "$pkg_mgr install -y python36"
        cki_run_cmd_pos "$python -V > /dev/null 2>&1" || \
            cki_abort_task "FAIL: Could not install python3!"
    fi
    if [[ $fwbranch != "master" ]]; then
        if [[ -n $STQE_STABLE_VERSION ]]; then
            cki_run_cmd_pos "git checkout $STQE_STABLE_VERSION" || \
                cki_abort_task "fail to checkout $STQE_STABLE_VERSION"
        fi
        if [[ -n $LIBSAN_STABLE_VERSION ]]; then
            typeset pip_cmd="$python -m pip install -U pip==19"
            cki_run_cmd_pos "$pip_cmd libsan==$LIBSAN_STABLE_VERSION" || \
                cki_abort_task "fail to install libsan==$LIBSAN_STABLE_VERSION"
        fi
    fi

    # install required packages
    cki_run_cmd_neu "bash env_setup.sh"

    cki_run_cmd_pos "$python setup.py install --prefix=" || \
        cki_abort_task "fail to install test framework"

    cki_pd

    return 0
}

function stqe_fini_fwroot
{
    typeset fwroot=$(stqe_get_fwroot)
    cki_run_cmd_neu "rm -rf $fwroot"
}
