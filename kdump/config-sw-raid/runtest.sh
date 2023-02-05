#!/bin/bash

# Copyright (C) 2015
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

set -x

RAID_DEVICE=${RAID_DEVICE:-"/raid1 /raid2"}
RAID_LEVEL=${RAID_LEVEL:-"0"}
KPATH=${KPATH:-"$K_DEFAULT_PATH"}
MP=${MP:-"/mnt/raid"}

CheckUnexpectedReboot

check_raid()
{
    mdadm --detail /dev/md0
    [ $? != 0 ] && {
        Log "- /dev/md0 is available!"
        return
    }
    Log "- Release /dev/md0"
    {
        mdadm --stop /dev/md0
        Log " - /dev/md0 is available now!"
    }
}

save_mdadm_config()
{
    # save mdadm config to /etc/mdadm.conf
    mdadm --detail --brief /dev/md0 >> /etc/mdadm.conf
    RhtsSubmit /etc/mdadm.conf

    # remove old mount point
    cat ${FSTAB_FILE}
    for i in $RAID_DEVICE; do
        sed -i "\#$i#d" ${FSTAB_FILE}
    done

    # add new mount point to fstab
    echo "/dev/md0                $MP              ext4    defaults         0 0" >> ${FSTAB_FILE}
    cat ${FSTAB_FILE}

    RhtsSubmit ${FSTAB_FILE}
    sync; sync; sync
}

config_software_raid()
{
    device_name=("")
    count=0

    for i in $RAID_DEVICE; do
        device_name[$count]=$(findmnt -kcno SOURCE "$i")
        (( count++ ))
    done

    Log "- The ready disk is ${device_name[*]}"

    # Release disk before create raid devices
    for i in ${device_name[@]}; do
        umount "$i"
    done

    case $RAID_LEVEL in
        0)
            Log "- Create raid0 devices."
            check_raid
            mdadm --create /dev/md0 --run --level raid0 --raid-devices 2 "${device_name[0]}" "${device_name[1]}"
            ;;
        1)
            Log "- Create raid1 devices."
            check_raid
            mdadm --create /dev/md0 --run --level raid1 --raid-devices 2 "${device_name[0]}" "${device_name[1]}"
            ;;
        5)
            Log "- Create raid5 devices."
            check_raid
            mdadm --create /dev/md0 --run --level raid5 --raid-devices 3 "${device_name[0]}" "${device_name[1]}" "${device_name[2]}"
            ;;
        *)
            MajorError "- Error raid level."
            ;;
    esac

    [ $? != 0 ] && MajorError "- Create raid$RAID_LEVEL failed."

    mdadm --detail /dev/md0
    mkfs.ext4 /dev/md0 > /dev/null
    mkdir -p "$MP"
    mount /dev/md0 "$MP"
    save_mdadm_config

    # Save RAID device for test clean up
    echo "/dev/md0" > "${K_RAID}"
    echo "${RAID_DEVICE}" >> "${K_RAID}"

    AppendConfig "ext4 /dev/md0" "path $KPATH"
    mkdir -p "$MP/$KPATH"
    echo "${MP%/}$KPATH" > "${K_PATH}"

    RestartKdump

    # Wait until initial reconstruction is ready for raid1 and raid5
    if [ "$RAID_LEVEL" = 1 ] || [ "$RAID_LEVEL" = 5 ]; then
        if [ "$RAID_LEVEL" = 1 ]; then
            expect_value="2/2"
        else
            expect_value="3/3"
        fi

        for i in {1..30}; do
            grep -i "${expect_value}" /proc/mdstat && break
            sleep 60
        done

        grep -i "${expect_value}" /proc/mdstat  || {
            Warn "Raid${RAID_LEVEL} resconstruction is not done in 30 mins."
        }
    fi

    cat /proc/mdstat


}

# ------ Start Here -------
Multihost 'config_software_raid'
