#!/bin/sh
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Source Kdump tests common functions.
. ../include/runtest.sh


THIN_MP=${THIN_MP:-"/"}  # Must start with '/'
THIN_KPATH=${THIN_KPATH:-"${K_DEFAULT_PATH}"}    # Must start with '/'
THIN_SIZE=${THIN_SIZE:-"2G"}
AUTO_EXTEND=${AUTO_EXTEND:-"false"}
RESTART_KDUMP=${RESTART_KDUMP:-"true"}

# --- start ---
CheckUnexpectedReboot


# @usage: ConfigThin
# @description: Reformat partition mounted at $THIN_MP to thin lvm and
#               configure it as kdump dump target
# THIN_MP: The point where the thin dump target is mounted.
# THIN_KPATH: The relative path on the dump target where the vmcore will be saved to.
#             By default '/var/crash'
# THIN_SIZE: Size of the THINPOOL. By default '2G'
# AUTO_EXTEND: Activate auto extend scenario. Default 'false'
# RESTART_KDUMP: Whether restart kdump service after updating kdump config. Default 'true'
ConfigThin(){
    if [ -z "${THIN_MP}" ] || [ "${THIN_MP}" = '/' ] || [ "${THIN_MP}" = '/boot' ] || [ "${THIN_KPATH:0:1}" != '/' ]; then
        Error "Invalid THIN_MP or THIN_KPATH."
        Log "THIN_MP must be provided and it cannot be root or boot partition. THIN_KPATH must start with '/'"
        return
    fi

    local dev_name=$(df ${THIN_MP} 2>&1 | sed -n 2p | awk '{print $1;}')
    [ -z "${dev_name}" ] && {
        Error "No dev found at ${THIN_MP}"
        LogRun "df ${THIN_MP}"
        return
    }

    # Reformat the partition mounted at $THIN_MP to thin lvm
    rpm -q --quiet lvm2 || InstallPackages lvm2

    local thinpool_log="thinpool.log"
    local thinpool_cmd="thinpool.cmd"

    local thin_size0=$THIN_SIZE
    local start_lvm_monitor="true"
    if [ "${AUTO_EXTEND}" != "false" ]; then
        thin_size0="50M"
        start_lvm_monitor="systemctl start lvm2-monitor && vgchange --monitor y"
        cp -f /etc/lvm/lvm.conf /etc/lvm/lvm.conf.old
        RhtsSubmit "/etc/lvm/lvm.conf.old"
cat <<EOF > /etc/lvm/lvm.conf
activation {
    thin_pool_autoextend_threshold = 70
    thin_pool_autoextend_percent = 20
    monitoring = 1
}
EOF
        RhtsSubmit "/etc/lvm/lvm.conf"
    fi

    cat <<EOF > "${thinpool_cmd}"
set -x
umount ${dev_name}
mkfs.xfs -f ${dev_name}
vgcreate vg00 -f ${dev_name}
lvcreate -L ${thin_size0} -T vg00/thinpool
lvcreate -V ${THIN_SIZE} -T vg00/thinpool -n crashvol
mkfs.xfs /dev/vg00/crashvol
${start_lvm_monitor}
mount /dev/vg00/crashvol ${THIN_MP}
systemctl status lvm2-monitor
set +x
EOF
    RhtsSubmit "${PWD}/${thinpool_cmd}"

    sh ${thinpool_cmd} > ${thinpool_log} 2>&1
    RhtsSubmit "${PWD}/${thinpool_log}"

    if ! mount | grep -q "crashvol"; then
        Error "Failed to create thinpool LVM. Read details in ${thinpool_cmd} and ${thinpool_log}"
        return
    fi

    LogRun "vgs -a"
    LogRun "lvs -a"

    # Update /etc/fstab
    cp -f ${FSTAB_FILE} fstab.old
    RhtsSubmit "${PWD}/fstab.old"

    sed -i "/ ${THIN_MP//\//\\\/} /d" ${FSTAB_FILE}
    local uuid=$(blkid -s UUID /dev/vg00/crashvol -o value)
    echo "UUID=${uuid} ${THIN_MP}    xfs   defaults   1 2" >> ${FSTAB_FILE}
    RhtsSubmit "${FSTAB_FILE}"

    # Configure Kdump target
    MP=${THIN_MP} KPATH=${THIN_KPATH} RESTART_KDUMP=${RESTART_KDUMP} ConfigFS
}

Multihost 'ConfigThin'
