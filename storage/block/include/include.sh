#!/bin/bash

#FILE=$(readlink -f "${BASH_SOURCE[0]}")
# shellcheck disable=SC2034
#CDIR=$(dirname "${FILE}")
#. /usr/share/beakerlib/beakerlib.sh   || exit 1
#. "$CDIR"/../../../cki_lib/libcki.sh || exit 1

function prepare_reboot()
{
# IA-64 needs nextboot set.
    if [ -e "/usr/sbin/efibootmgr" ]; then
        EFI=$(efibootmgr -v | grep BootCurrent | awk '{ print $2}')
        if [ -n "$EFI" ]; then
            rlLog "Updating efibootmgr next boot option to $EFI according to BootCurrent"
            rlRun "efibootmgr -n $EFI"
        elif [[ -z "$EFI" && -f /root/EFI_BOOT_ENTRY.TXT ]] ; then
            os_boot_entry=$(</root/EFI_BOOT_ENTRY.TXT)
            rlLog "Updating efibootmgr next boot option to $os_boot_entry according to EFI_BOOT_ENTRY.TXT"
            rlRun "efibootmgr -n $os_boot_entry"
        else
            rlLog "Could not determine value for BootNext!"
        fi
    fi
}

function check_log()
{
    rlRun "dmesg | grep -i 'Call Trace:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'kernel BUG at'" 1 "check the errors"
#    rlRun "dmesg | grep 'BUG:'" 1 "check the errors"
#    rlRun "dmesg | grep -i 'WARNING:'" 1 "check the errors"
}

function get_free_disk()
{
    var=$1
    disk_list=()
    echo "will get free disk for testing"

    if [ ! ${var} ];then
        disk="/dev/sd? /dev/nvme???"
    elif [ ${var} == ssd ];then
        disk="/dev/sd?"
    elif [ ${var} == nvme ];then
        disk="/dev/nvme???"
    else
        echo "Parameter passing error"
        exit 1
    fi

    for i in $(ls ${disk} |  awk -F / '{print $3}');do
        n=$(cat /proc/partitions  |awk '{print $4}' |egrep $i |wc -l)
        if [ $n = 1 ];then
            echo "$i have no partition"
            disk_list+=( /dev/$i)
        fi
    done

    echo "free device: ${disk_list[*]}"
    for i in $(seq 0 ${#disk_list[@]});do
        eval "dev$i=${disk_list[$i]}"
    done
}

function get_nvme_pci_id()
{
    NVME_DISK=$1
    NVME_CHAR=${NVME_DISK:0:5}
    TEST_DEV_SYSFS=/sys/block/$NVME_DISK/device
    uname -r | grep -qE "el9|el10" && TEST_DEV_SYSFS="$TEST_DEV_SYSFS/$NVME_CHAR"
    readlink -f "$TEST_DEV_SYSFS" | \
        grep -Eo '[0-9a-f]{4,5}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]' | \
        tail -1
}

function clear_partition()
{
    boot_disk=$(lsblk -no MOUNTPOINT,PKNAME | awk '$1=="/boot"{print $2}' | head -n1)
    echo "Boot is on disk: $boot_disk"

    all_disks=$(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}')
    for disk in $all_disks; do
        if [[ "$disk" == "$boot_disk" ]]; then
            echo "Skipping /dev/$disk (contains /boot)"
            continue
        fi

        echo "Processing /dev/$disk: removing all partitions..."
        part_numbers=$(parted -s /dev/$disk print | awk '/^ [0-9]+/{print $1}')

        for num in $part_numbers; do
            echo "  Deleting partition $num on /dev/$disk"
            parted -s /dev/$disk rm "$num"
        done
        echo "Finished wiping /dev/$disk"
    done
}
