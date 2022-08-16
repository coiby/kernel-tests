#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Sysctl value test
#   Description: Check sysctl defalut value for unintentional changes
#   Author: Chao Ye <cye@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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

function bzsysctl()
{
    rpm -q nfs-utils || yum install -y nfs-utils

    if uname -r | grep ^4.18.0; then
        base_live="rhel8-sysctl_live.log"
        base_conf="rhel8-sysctl_conf.log"
    elif uname -r | grep ^3.10.0; then
        base_live="rhel7-sysctl_live.log"
        base_conf="rhel7-sysctl_conf.log"
    else
        echo "=====OS Not Supported====="
        return 0
    fi

    let ret=0
    mp=$(mktemp -d)
    if mount vmcore.usersys.redhat.com:/data/sysctl ${mp}; then
        pushd ${mp}
        echo "=====$(uname -r)-$(hostname)-sysctl_conf====="
        grep -Ev "^$|[#;]" /usr/lib/sysctl.d/ /etc/sysctl.d/ -rI | tee $(uname -r)-$(hostname)-sysctl_conf.log
        echo "=====$(uname -r)-$(hostname)-sysctl_live====="
        sysctl -ae | tee $(uname -r)-$(hostname)-sysctl_live.log
        echo "=====Check $(uname -r)-$(hostname)-sysctl_live with ${base_live}====="
        for key in $(cut -f1 -d= ${base_live}); do
            if ! grep -q "$(sysctl ${key})" ${base_live}; then
                let ret+=1
                echo "=====live:${key} FAIL====="
                echo "Previous: $(grep ${key} ${base_live})"
                echo "Current:  $(sysctl ${key})"
            fi
        done
        echo "=====Check $(uname -r)-$(hostname)-sysctl_conf with ${base_conf}====="
        export IFS='\$'
        for conf in $(cat ${base_conf}); do
            if ! grep -q ${conf} $(uname -r)-$(hostname)-sysctl_conf.log; then
                let ret+=1
                key=$(cut -f1 -d= ${conf} | cut -f2 -d:)
                echo "=====conf:${key} FAIL====="
                echo "Previous: $(grep ${key} ${base_conf})"
                echo "Current:  $(grep ${key} $(uname -r)-$(hostname)-sysctl_conf.log)"
            fi
        done
        popd
        umount ${mp}
        if [ ${ret} -eq 0 ]; then
            echo "=====sysctl Test PASS====="
        else
            echo "=====sysctl Test FAIL====="
        fi
        return $ret
    else
        echo "=====Mount NFS Server FAIL====="
        return 1
    fi
}
