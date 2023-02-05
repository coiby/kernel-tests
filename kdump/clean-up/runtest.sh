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

CheckUnexpectedReboot

# @usage: removeRaid
# @description: release raid and clean up raid configurations
RemoveRaid() {
    [ ! -f "${K_RAID}" ] && return 0

    local md_device
    local md_details
    local raid_devices
    local count=0

    Log "Removing RAID"

    md_device=$(sed -n "1p" "${K_RAID}")    # e.g. /dev/md0
    dev_mounts=($(sed -n "2p" "${K_RAID}")) # e.g. /raid0 /raid1

    md_details=$(mdadm --detail --brief "${md_device}")
    count=$(mdadm --detail "${md_device}" | awk -F ':' '/Raid Devices/{print $2}')
    [ "${count}" -ge 2 ] && {
        # get the devices which are grouped to the md device.
        # e.g. /dev/sda3 /dev/sda4
        raid_devices=$(mdadm --detail "${md_device}" | tail -n "$count" | awk '{print $NF}')
    }
    Log "Find md_device: ${md_device}"
    Log "Find raid devices: ${raid_devices}"
    # umount/stop md, and remove superblock
    umount "${md_device}"
    mdadm --stop "${md_device}" || {
        Error "Failed to umount and stop ${md_device}"
    }
    Log "Umounted and stopped ${md_device}"

    Log "Clear superblock info and re-mount ${raid_devices} after formatting"
    [ -n "${raid_devices}" ] && {
        local idx=0
        for dev in ${raid_devices}; do
            # clear superblock info from devices and re-format/mount them
            mdadm --zero-superblock "${dev}"
            mkfs.ext4 "${dev}" >/dev/null
            mount "${dev}" "${dev_mounts[$idx]}"
            ((idx++))
        done
    }

    Log "Remove entries in /etc/mdadm.conf and ${FSTAB_FILE}"
    sed -i "s|${md_details}||" /etc/mdadm.conf
    sed -i "s|^${md_device}.*||" ${FSTAB_FILE}

    Log "Raid has been removed and devices have been restored successfully."
}

RestoreRAW(){
    [ ! -f ${K_RAW} ] && return

    # This function is to restore the raw disk to it's original format

    # The raw device info is stored in ${K_RAW}. example:
    # /dev/vda2,ext4,/raw
    # UUID=d3167b37-3229-45e8-9707-f6d125adb7a0 /raw  ext4    defaults        1 2

    Log "Restore RAW device"
    local dev=$(awk -F',' 'FNR==1 {print $1}' ${K_RAW})
    local fstype=$(awk -F',' 'FNR==1 {print $2}' ${K_RAW})
    local mp=$(awk -F',' 'FNR==1 {print $3}' ${K_RAW})
    [ -z "$fstype" ] && return

    # Reformat and remount the raw disk if it's not yet mounted
    if mount | egrep -q "\s+$mp\s+"; then
        Log "$mp is already mounted"
    else
        LogRun "mkfs.$fstype $dev; mount $dev $mp"
        [ $? -ne 0 ] && {
            Error "Failed to reformat and mount RAW device"
            return 1
        }
    fi

    return
}

RestoreFSTAB(){
    # The UUID of the raw parition needs to be updated in fstab
    # This has to be run after RestoreRAW. Otherwise UUID is not generated.
    if [ -f ${K_RAW} ]; then
        local dev=$(awk -F',' 'FNR==1 {print $1}' ${K_RAW})
        local mp=$(awk -F',' 'FNR==1 {print $3}' ${K_RAW})
        local uuid=$(lsblk --nodeps -no UUID $dev)

        local temp_mp="${mp////\\/}"
        local file=${FSTAB_FILE}
        [ -f "${FSTAB_FILE}.bk" ] && file=${FSTAB_FILE}.bk
        sed -i -E "/[ \t]${temp_mp}[ \t]/s/UUID=([a-zA-Z0-9-]+)/UUID=${uuid}/g" ${file}
    fi

    [ -f "${FSTAB_FILE}.bk" ] && LogRun "cp -f ${FSTAB_FILE}.bk ${FSTAB_FILE}"

    RhtsSubmit ${FSTAB_FILE}
}

CleanUp() {
    local nfs_mount
    local vmcore_path=""

    if [ -f "${K_NFS}" ]; then
        Log "Kdump was set to a NFS target. No data will be remoreved on NFS server"
        Log "Unmount NFS server"

        nfs_mount=$(cat "${K_NFS}")
        LogRun "umount \"${nfs_mount}\""

        # It will remove the vmcore files copied by 'copy-nfs' task
        if [ -f "${K_PATH}" ]; then
            vmcore_path=$(cat "${K_PATH}")
            vmcore_path="${nfs_mount}/${vmcore_path}"
        fi

    elif [ -f "${K_PATH}" ]; then
        vmcore_path=$(cat "${K_PATH}")
    else
        vmcore_path="${K_DEFAULT_PATH}"
    fi

    if [ -d "${vmcore_path}" ]; then
        # Check again if the vmcore path is a mounted remoted file system.
        # If yes, do not remove any files under the path
        df -T "${vmcore_path}" | tail -n 1 | awk '{print $2}' | grep -q nfs
        [ $? -ne 0 ] && {
            Log "Remove files in ${vmcore_path}"
            rm -rf "${vmcore_path}"/*
        }
    fi

    RemoveRaid
    RestoreRAW
    RestoreFSTAB

    Log "Restore configurations"
    [ -f "${KDUMP_CONFIG}.bk" ] && LogRun "cp -f ${KDUMP_CONFIG}.bk ${KDUMP_CONFIG}"
    [ -f "${KDUMP_SYS_CONFIG}.bk" ] && LogRun "cp -f ${KDUMP_SYS_CONFIG}.bk ${KDUMP_SYS_CONFIG}"
    [ -f "${INITRD_IMG_PATH}.bk" ] && LogRun "cp -f ${INITRD_IMG_PATH}.bk ${INITRD_IMG_PATH}"

    Log "Remove kdump-pre/post stamps"
    [ -f "/root/kdump-pre.stamp" ] && LogRun "rm -f /root/kdump-pre.stamp"
    [ -f "/root/kdump-post.stamp" ] && LogRun "rm -f /root/kdump-post.stamp"
    [ -f "/root/module.stamp" ] && LogRun "rm -f /root/module.stamp"

    Log "Remove temporary files"
    LogRun "rm -f ${K_NFS} ${K_PATH} ${K_REBOOT}" ${K_RAW}

    Log "Reset Network configurations"

    Log "Network status before restoration"
    LogRun "ip add show"

    TESTNICS=$(ip route | awk '$1=="default" {print $5}')

    ifcfgdir="/etc/sysconfig/network-scripts"

    if [ -n "$TESTNICS" ] && [ -f "${K_NET_IFCFG}" ]; then
        Log "Restoring net device: $TESTNICS"
        for NIC in $TESTNICS; do
            # Ensure that the network configuration is modified
            _ifcfg=$ifcfgdir/ifcfg-$NIC
            # Restore old backup file
            if [ ! -f $_ifcfg ]; then
                con_name=$(nmcli d show $NIC | grep GENERAL.CONNECTION | awk '{print $2}')
                [ -f "${K_NMCLI_PATH}/${con_name}.nmconnection.bk" ] &&
                    LogRun "cp -f ${K_NMCLI_PATH}/${con_name}.nmconnection.bk ${K_NMCLI_PATH}/${con_name}.nmconnection" &&
                    rm -f ${K_NET_IFCFG}
            elif [ -f "${_ifcfg}.bk" ]; then
                LogRun "/bin/cp -rf ${_ifcfg}.bk $_ifcfg"
                rm -f ${K_NET_IFCFG}
            fi
        done

        nmcli connection reload
        nmcli device reapply $NIC
        Log "Network status after restoration"
        LogRun "ip add show"
    fi

    export NOKDUMPRD=true
    RestartKdump
    unset NOKDUMPRD
}

#+---------------------------+

Multihost 'CleanUp'
