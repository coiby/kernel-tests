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
    rlRun "dmesg | grep 'BUG:'" 1 "check the errors"
    rlRun "dmesg | grep -i 'WARNING:'" 1 "check the errors"
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
