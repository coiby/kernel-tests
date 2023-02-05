#!/bin/sh

# Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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

TARGET_NAME=${TARGET_NAME:-"iqn.2019-06.com.kdump:server0"}
FS_TYPE=${FS_TYPE:-"xfs"}
MP=${MP:-"/mnt/iscsi"}

CheckUnexpectedReboot

if echo "${CLIENTS}" | grep -qi "${HOSTNAME}"; then
    Log "- Run config-ssh test as client."

    # This section will
    # 1) Allow client to discover and login to server targets
    # 2) Configure kdump.conf to the iscsi targets
    # 3) Save dump path in K_NFS and K_PATH for latet vmcore analysis.
    # 4) Config /etc/fstab for connecting iscsi target at startup.

    # Find iscsi targets
    rpm -q --quiet iscsi-initiator-utils || InstallPackages iscsi-initiator-utils

    # use same name for target and initiator
    echo "InitiatorName=${TARGET_NAME}" > /etc/iscsi/initiatorname.iscsi
    systemctl restart iscsid
    systemctl restart iscsi

    TEST="${TEST}/client"
    Log "- Blocked till the server side is ready."
    rstrnt-sync-block -s "DONE" "${SERVERS}" --timeout 3600

    server_ip=$(getent ahosts "${SERVERS}" | grep -v : | head -n 1 | awk '{print $1}')
    iscsiadm --mode discovery --type sendtargets --portal "${server_ip}" | grep "${TARGET_NAME}"
    [ $? -ne 0 ] && {
        iscsiadm --mode discovery --type sendtargets --portal "${server_ip}"
        MajorError "- Failed to find iscsi target '${TARGET_NAME}' from ${server_ip}"
    }

    old_lsblk_count=$(lsblk -f | wc -l)
    iscsiadm -m node --target "${TARGET_NAME}" --portal "${server_ip}" --login
    [ $? -ne 0 ] && MajorError "- Failed to login iscsi target '${TARGET_NAME}' on ${server_ip}"

    sleep 5 # sleep 5s for new iscsi device.
    new_lsblk_count=$(lsblk -f | wc -l)
    [ "$new_lsblk_count" -gt "$old_lsblk_count" ] || {
        lsblk -f
        MajorError "- No iscsi disk is added"
    }


    # The newly added iscsi may not be the last one shown on the lsblk list. Check it in /dev/disk instead
    # target_dev="/dev/$(lsblk -f | tail -n 1 | awk '{print $1}')"
    target_dev="/dev/$(ls -la /dev/disk/by-path/ip-*${TARGET_NAME}* | awk -F'/' '{print $NF}')"
    [ "${target_dev}" = "/dev/" ] && {
        ls -la /dev/disk/by-path/
        MajorError "- No iscsi disk froun in /dev/disk/by-path"
    }

    mkfs.${FS_TYPE} "${target_dev}"
    sleep 15 # sleep 5s for lsblk update

    target_uuid=$(lsblk -f ${target_dev} | tail -n 1 | awk '{print $3}')
    lsblk -f

    # Use the fixed 'path' option $HOSTNAME to identify the
    # vmcores of different clients because later case can fetch
    # the vmcore not belonging to itself if different clients
    # concurrently dumping to $NFS_SERVER.
    AppendConfig "path /${HOSTNAME}"
    AppendConfig "${FS_TYPE} UUID=${target_uuid}"
    echo "/${HOSTNAME}" > "${K_PATH}"
    mkdir -p "${MP}"
    mount "UUID=${target_uuid}" "${MP}"
    mkdir -p "${MP}/${HOSTNAME}"
    echo "${MP}" > "${K_NFS}"
    RestartKdump

    echo "UUID=${target_uuid}  ${MP}  ${FS_TYPE}  defaults,_netdev 0 0" >> ${FSTAB_FILE}
    RhtsSubmit ${FSTAB_FILE}
    Log "- Client finished."
    rstrnt-sync-set -s "DONE"

elif echo "${SERVERS}" | grep -qi "${HOSTNAME}"; then
    Log "- Run config-iscsi test as server."
    # This section will configure an iscsi target using targetcli

    # Get server IP
    server_ip=$(ip ad show | grep 'inet ' | grep global | awk -F' ' '{print $2}' | awk -F'/' '{print $1}')

    # Create iscsi target
    TEST="${TEST}/server"
    rpm -q --quiet targetcli || InstallPackages targetcli

    iscsi_dev="/root/kdump.img"
    [ -f "${iscsi_dev}" ] && \rm -f "${iscsi_dev}"
    dd if=/dev/zero of=/root/kdump.img bs=1024 count=1048576

    targetcli /backstores/fileio create iscsi_data "${iscsi_dev}"
    targetcli /iscsi create "${TARGET_NAME}"
    targetcli /iscsi/${TARGET_NAME}/tpg1/luns create /backstores/fileio/iscsi_data
    targetcli /iscsi/${TARGET_NAME}/tpg1/portals ls | grep 0.0.0.0 && {
        targetcli /iscsi/${TARGET_NAME}/tpg1/portals delete 0.0.0.0:0
        targetcli /iscsi/${TARGET_NAME}/tpg1/portals delete 0.0.0.0 3260
    }
    targetcli /iscsi/${TARGET_NAME}/tpg1/portals create "${server_ip}"
    targetcli /iscsi/${TARGET_NAME}/tpg1/acls create "${TARGET_NAME}"

    targetcli /iscsi ls
    targetcli /iscsi ls | grep "${iscsi_dev}" || MajorError "- Failed to create iscsi lun on ${iscsi_dev}"
    targetcli /iscsi ls | grep "${server_ip}:3260" || MajorError "- Failed to create iscsi portal ${server_ip}:3260"

    Log "- Server finished."
    rstrnt-sync-set -s "DONE"
    rstrnt-sync-block -s "DONE" "${CLIENTS}" --timeout 3600

    if [ "$?" -ne 0 ]; then
        MajorError "- Not receiving DONE signal from server"
    fi
else
    Error "Neither server nor client"
fi

Report

