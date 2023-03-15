#!/bin/sh

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Test Bug 1924987 - [RHEL8.4] Fail to start kdump service if /etc/kdump.conf is empty
#   Author: Ruowen Qin <ruqin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source Kdump tests common functions.
. ../include/runtest.sh


CheckKdumpConfFromInitramfs() {
    local option=$1
    local squash_file
    local kdump_bootdir="/boot"

    Log "Check kdump.conf in kdump initramfs img"
    local kdump_initramfs_path="${INITRD_KDUMP_IMG_PATH}"

    # Locate the kdump initramfs img
    if [ ! -f "${kdump_initramfs_path}" ]; then
        # Try again in /var/lib/kdump
        # From RHEL-8.5 kdump img will be written to /var/lib/kdump
        # if /boot is readonly (BZ1918499)
        kdump_initramfs_path=${kdump_initramfs_path//boot/var/lib/kdump}
        if [ ! -f "${kdump_initramfs_path}" ]; then
            Error "Kdump initramfs doesn't exist: $kdump_initramfs_path"
            return
        fi
    fi

    # Check kdump initramfs in another workdir
    [ -d "./workdir" ] && rm -rf workdir
    mkdir workdir && pushd ./workdir >/dev/null

    Log "Unpack initramfs and squashed root img"
    if LogRun "lsinitrd --unpack ${kdump_initramfs_path}"; then
        if ! ls | grep -qi squash-root.img; then
            # for RHEL8.4 and older, the root image is in squash folder
            squash_file="squash/root.img"
        else
            # for RHEL8.5 and newer, the root image is in current folder
            squash_file="squash-root.img"
        fi
        [ -d "./squashfs-root" ] && rm -rf ./squashfs-root
        LogRun "unsquashfs -n $squash_file >/dev/null"

        Log "Locate and check content of kdump.conf file in initramfs"
        local kdump_config_insquash=./kdump.conf.insquash
        \cp -f squashfs-root/${KDUMP_CONFIG} ${kdump_config_insquash} || {
            Error "Failed to find kdump.conf in inistramfs"
            return
        }

        # check file empty and upload kdump.conf
        # Expect a simple default kdump.conf is added to the initramfs img
        RhtsSubmit "$(pwd)/${kdump_config_insquash}"
        [ $(wc -l < ${kdump_config_insquash} ) -eq 2 ] &&
            awk 'NR==1' ${kdump_config_insquash} | grep -Pq "\A(?:xfs|ext4) \/dev\/.+" &&
            awk 'NR==2' ${kdump_config_insquash} | grep -Pq "path \/var\/crash\/\Z" ||
            Error "Default kdump file doesn't pack into initramfs. Check ${kdump_config_insquash} for details"
    else
        Error "Failed to unpack initramfs."
    fi

    popd >/dev/null
}

# Bug 1924987 - [RHEL8.4] Fail to start kdump service if /etc/kdump.conf is empty
# Fixed in RHEL-8.5 kexec-tools-2.0.20-57
EmptyConfCheck() {
    CheckSkipTest kexec-tools 2.0.20-57 && return

    # Make sure default path "/var/crash" exists
    # If /var/crash is mounted on a remote device it's not suitable for this test
    local vmcore_path="/var/crash"
    if [ ! -d "${vmcore_path}" ]; then
        Skip "Dump target ${vmcore_path} doesn't exist"
        return
        if df -T "${vmcore_path}" | tail -n 1 | awk '{print $2}' | grep -q nfs; then
            Skip "Dump target ${vmcore_path} is a mounted on remote file system"
            LogRun "df -T ${vmcore_path}"
            return
        fi
    fi

    # Backup the kdump.conf
    [ -f "./kdump.conf.bk" ] || \cp "${KDUMP_CONFIG}" ./kdump.conf.bk

    # Empty the kdump.conf file and restart kdump service
    Log "Create an empty kdump config and restart kdump service"
    echo -n > "${KDUMP_CONFIG}"
    sync; sync; sync

    local restart_log=empty_conf_restart.log
    LogRun "kdumpctl restart &> ${restart_log}"
    local retval=$?

    RhtsSubmit "$(pwd)/${restart_log}"

    [ "$retval" -ne 0 ] && {
        Error "Failed to restart kdump service."
        return
    }

    # Check the file in initramfs
    # Kdump may use the non-debug kernel/initramfs when system is running on a debug kernel
    if grep -q "Trying to use" "${restart_log}" && grep -q -v "Fallback" "${restart_log}"; then
        CheckKdumpConfFromInitramfs nondebug
    else
        CheckKdumpConfFromInitramfs
    fi


    # Restore kdump config
    Log "Restore kdump config"
    mv -f ./kdump.conf.bk "${KDUMP_CONFIG}"
    RestartKdump
}

MultihostStage "$(basename "${0%.*}")" EmptyConfCheck
