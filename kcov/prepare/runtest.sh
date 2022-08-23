#!/bin/sh

# Copyright (c) 2010 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Hushan Jia <hjia@redhat.com>

. /usr/bin/rhts_environment.sh

# source include file
. ../include/include.sh

set -x

TEST="/kcov/prepare"

setup()
{
    # prepare the kernel for coverage collection
    log "Red Hat release: $(cat /etc/redhat-release)"
    log "Running on $(arch), kernel $(uname -r)"

    # setting configs
    log "setting configs"
    if [ -n "$KDIR" ]; then
        KCOV_KDIR=$KDIR
    fi

    if [ ! -e /sys/kernel/debug/gcov ]; then
        cki_abort_recipe "kernel doesn't seem to support gcov";
        exit
    fi

    log "write config"
    echo "KDIR=$KCOV_KDIR" > $KCOV_CONF
    if [ -n "$ONLY_FINAL_INFO" ]; then
        echo "ONLY_FINAL_INFO=$ONLY_FINAL_INFO" >> $KCOV_CONF
    fi
    log "submit config"
    rhts-submit-log -l $KCOV_CONF

    rpm -q ${KERNEL_GCOV}
    if [ $? -ne 0 ]; then
        # Expects cki repo with kernel rpms to be configured
        log "install gcov data files"
        if [[ -e /run/ostree-booted ]]; then
            rpm-ostree install -A ${KERNEL_GCOV}
            if [ $? -ne 0 ]; then
                cki_abort_recipe "Cannot install the gcov data files package.";
                exit
            fi
        else
            dnf install -y ${KERNEL_GCOV}
            if [ $? -ne 0 ]; then
                cki_abort_recipe "Cannot install the gcov data files package.";
                exit
            fi
        fi
    fi

    install_lcov

    # Enable NFS service on startup to make sure sunrpc module is loaded,
    # otherwise we see errors like
    # "lcov: ERROR: subdirectory net/sunrpc not found" in kcov/end if
    # "net/sunrpc" is in KDIR, but the test didn't load it.
    # This is just a workaround
    chkconfig nfs on >/dev/null 2>&1
    systemctl enable nfs-server >/dev/null 2>&1

    # gcov needs tens of hours to process xfs_sb.c on RHEL7, workaround it
    # by setting geninfo_gcov_all_blocks = 0 to /etc/lcovrc
    # see Bug 1290759 for details
    echo "geninfo_gcov_all_blocks = 0" >> /etc/lcovrc

    log "reboot to make sure all the changes are in effect"

    touch ./kernel_installed

    rhts-reboot
}

verify()
{
    log "after reboot"
    log "current kernel is $(uname -r)"
    if [ ! -e /sys/kernel/debug/gcov ]; then
        cki_abort_recipe "not running on gcov kernel."
        exit
    fi

    log "proc entries: $(ls /sys/kernel/debug/gcov)"

    ls $GCOV_BASEDIR/
    if [ $? -ne 0 ]; then
        cki_abort_recipe "${KERNEL_GCOV} files were not available after reboot"
        exit
    fi
    pass
}

if [ ! -e ./kernel_installed ]; then
    setup
else
    verify
fi
