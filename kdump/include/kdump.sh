#!/bin/bash
# shellcheck disable=SC2154

((KD_KDUMP_SH)) && return || KD_KDUMP_SH=1

# ---------------- Basic Configurations for Kdump Service  ------------------------ #

# @usage: DefKdumpMem
# @description:
#     It returns crash memory range (crashkernel=XXXM) based on
#     system release and arch. This is usually used when crashkernel=auto is
#     is not supported (e.g. Fedora) or when system memory is lower than the
#     memory threshold required by crashkernel=auto function.
# @return:
#     Crash kernel memory range. e.g. crashkernel=XXXM
#     For RHEL8 and CentOS8 - the crashkernel value is the same like RHEL-8.10.
#     For RHEL9 and CentOS9 - the crashkernel value is the same like RHEL-9.4.
DefKdumpMem()
{
    local args=""

    if $IS_RHEL6; then
        if   [[ "${K_ARCH}" == i?86     ]]; then args="crashkernel=128M"
        elif [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=128M"
        elif [[ "${K_ARCH}"  = "ppc64"  ]]; then args="crashkernel=256M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=128M"
        fi

    elif $IS_RHEL7; then
        if   [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=160M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=160M"
        elif [[ "${K_ARCH}"  = ppc64*  ]]; then
            args="crashkernel=0M-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        elif [[ "${K_ARCH}"  = "aarch64"  ]]; then args="crashkernel=512M"
        fi

    elif $IS_RHEL8 || $IS_CentOS8; then
        if   [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=0G-4G:192M,4G-64G:256M,64G-:512M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=0G-4G:192M,4G-64G:256M,64G-:512M"
        elif [[ "${K_ARCH}"  = ppc64*  ]]; then
            args="crashkernel=0G-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
            [[ "$1" = fadump ]] && args="crashkernel=0G-16G:768M,16G-64G:1G,64G-128G:2G,128G-1T:4G,1T-2T:6G,2T-4T:12G,4T-8T:20G,8T-16T:36G,16T-32T:64G,32T-64T:128G,64T-:180G"
        elif [[ "${K_ARCH}"  = "aarch64"  ]]; then args="crashkernel=480M"
        fi

    elif $IS_RHEL9 || $IS_CentOS9; then
        if   [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=0G-4G:192M,4G-64G:256M,64G-:512M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=0G-4G:192M,4G-64G:256M,64G-:512M"
        elif [[ "${K_ARCH}"  = ppc64*  ]]; then
            args="crashkernel=0G-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
            [[ "$1" = fadump ]] && args="crashkernel=0G-16G:768M,16G-64G:1G,64G-128G:2G,128G-1T:4G,1T-2T:6G,2T-4T:12G,4T-8T:20G,8T-16T:36G,16T-32T:64G,32T-64T:128G,64T-:180G"
        elif [[ "${K_ARCH}"  = "aarch64"  ]]; then args="crashkernel=0G-4G:256M,4G-64G:320M,64G-:576M"
        fi

    elif $IS_RHEL10 || $IS_CentOS10; then
        if   [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=0G-4G:192M,4G-64G:256M,64G-:512M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=0G-4G:192M,4G-64G:256M,64G-:512M"
        elif [[ "${K_ARCH}"  = ppc64*  ]]; then
            args="crashkernel=0G-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
            [[ "$1" = fadump ]] && args="crashkernel=0G-16G:768M,16G-64G:1G,64G-128G:2G,128G-1T:4G,1T-2T:6G,2T-4T:12G,4T-8T:20G,8T-16T:36G,16T-32T:64G,32T-64T:128G,64T-:180G"
        elif [[ "${K_ARCH}"  = "aarch64"  ]]; then args="crashkernel=0G-4G:256M,4G-64G:320M,64G-:576M"
        fi

    elif $IS_FC; then
        if   [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=0G-4G:192M,4G-64G:256M,64G-:512M"
        elif [[ "${K_ARCH}"  = "s390x"  ]]; then args="crashkernel=0G-4G:192M,4G-64G:256M,64G-:512M"
        elif [[ "${K_ARCH}"  = ppc64*  ]]; then
            args="crashkernel=0G-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        elif [[ "${K_ARCH}"  = "aarch64"  ]]; then args="crashkernel=0G-4G:256M,4G-64G:766M,64G-:1G"
        fi

    elif $IS_RHEL5; then
        if   [[ "${K_ARCH}" == i?86     ]]; then args="crashkernel=128M@16M"
        elif [[ "${K_ARCH}"  = "x86_64" ]]; then args="crashkernel=128M@16M"
        elif [[ "${K_ARCH}"  = "ppc64"  ]]; then args="crashkernel=256M@32M xmon=off"
        elif [[ "${K_ARCH}"  = "ia64"   ]]; then args="crashkernel=512M@256M";
            # the larger IA-64 box, the more kdump memory needed
            grep -qE '^ACPI:.*(rx8640|SGI)' /var/log/dmesg &&
            args="crashkernel=768M@256M"
        fi
    fi

    echo "$args"
}

# @usage: IfMemoryAboveThreshold
# @description: Check if memory is above the threshold required by
#               auto crash kernel reservation on rhel7.
# @return:
#     0 - Above the threshold. Valid for auto reservation,
#     1 - Below the threshold. Invalid for auto reservation.
# @to-do: Add memory threshold check for rhel6
IfMemoryAboveThreshold()
{
    # alternative in x86_64:
    # dmidecode -t 17 | grep "Size.*MB" | awk '{s+=$2} END {print s}'
    local total_mem mem

    total_mem=$(lshw -short | grep -i 'System Memory' | awk '{print $3}')
    if $IS_RHEL6 ; then
            mem=$(echo $total_mem | sed 's/...$//')
    else
            mem=${total_mem::-3}
    fi

    if [[ "$total_mem" =~ "TiB" ]]; then
        mem=$((mem*1024*1024))
    elif [[ "$total_mem" =~ "GiB" ]]; then
        mem=$((mem*1024))
    fi

    local retval=1
    local result="below"

    if $IS_RHEL7; then
        if   [[ "${K_ARCH}" = "x86_64" ]] && [ $mem -ge 2048 ]; then
            retval=0
        elif [[ "${K_ARCH}" = "ppc64"  ]] && [ $mem -ge 2048 ]; then
            retval=0
        elif [[ "${K_ARCH}" = "ppc64le" ]] && [ $mem -ge 2048 ]; then
            retval=0
        elif [[ "${K_ARCH}" = "s390x" ]] && [ $mem -ge 4096 ]; then
            retval=0
        elif [[ "${K_ARCH}" = "aarch64" ]] && [ $mem -ge 2048 ]; then
            retval=0
        fi
    elif $IS_RHEL8 || $IS_RHEL9 || $IS_FC; then
        if   [[ "${K_ARCH}" = "x86_64" ]] && [ $mem -ge 1024 ]; then
            retval=0
        elif [[ "${K_ARCH}" = "ppc64"  ]] && [ $mem -ge 2048 ]; then
            retval=0
        elif [[ "${K_ARCH}" = "ppc64le" ]] && [ $mem -ge 2048 ]; then
            retval=0
        elif [[ "${K_ARCH}" = "s390x" ]] && [ $mem -ge 1024 ]; then
            retval=0
        elif [[ "${K_ARCH}" = "aarch64" ]] && [ $mem -ge 2048 ]; then
            retval=0
        fi
    fi

    [ "${retval}" -eq 0 ] && result=above

    Log "System total memory (${total_mem}) is $result the auto threshold"
    return $retval
}


# @usage: CheckAutoReservation
# @description: Check if it's in auto mode and crash memory is reserved.
#               when sysetm memory is above memory threshold
# @return:
#     0 - Pass. It's auto mode and crash memory is reserved.
#     1 - Fail. It's not auto mode or no memory is reserved.
CheckAutoReservation()
{
    Log "Check crash memory auto reserveration."

    # Skip if the system doesn't support crash kernel auto reservation
    IfMemoryAboveThreshold || return 0

    # crashkernel=xxxM should present if RHEL6 or RHEL9+
    # crashkernel=auto should presents in RHEL7/RHEL8
    local crashkernel_str="crashkernel="
    if $IS_RHEL7 || $IS_RHEL8; then
        crashkernel_str="crashkernel=auto"
    fi

    grep -q "${crashkernel_str}" < /proc/cmdline
    [ $? -ne 0 ] && {
        Error "Default $crashkernel_str doesn't present in kernel cmdline"
        return 1
    }

    # Return 1 if no crash memory reserved.
    if grep -qoE "fadump=\w+" /proc/cmdline ; then
        if CommandExists journalctl ; then
            journalctl | grep -i "firmware-assisted" | grep -i -q "Reserved"
        else
            dmesg | grep -i "firmware-assisted" | grep -i -q "Reserved"
        fi
        [ $? -ne 0 ] && return 1
    else
        Log "Reserved: $(cat /sys/kernel/kexec_crash_size)"
        [ "$(cat /sys/kernel/kexec_crash_size)" -eq 0 ] && return 1
    fi
    return 0
}

GetConfig() {
    awk '
        match($0, /^'${1}'[[:blank:]]+([^#]*)/, v) {
            print gensub(/[[:blank:]]*$/, "", 1, v[1]);
        }
    ' "${KDUMP_CONFIG}"
}

CheckConfig()
{
    if [ ! -f "${KDUMP_CONFIG}" ]; then
        # [ -n "${1}" ] && rstrnt-sync-set -s "DONE"
        FatalError "Unable to find ${KDUMP_CONFIG}"
    fi
}

# Removing kdump config lines starting with $opt
RemoveConfig()
{
    local opt=$1

    if [[ ! "${opt}" =~ ^[a-zA-Z_\s]+$ ]]; then
        Erorr "Invalid kdump option. Only alphabets, understore and space are allowed"
        return 1
    fi

    Log "Modifying ${KDUMP_CONFIG}"

    Log "Removing settings for ${opt}"
    sed -i "/^${opt}/d" ${KDUMP_CONFIG}

    RhtsSubmit "${KDUMP_CONFIG}"
}

AppendConfig()
{
    Log "Modifying ${KDUMP_CONFIG}"

    if [ $# -eq 0 ]; then
        Warn "Nothing to append."
        return 0
    fi

    while [ $# -gt 0 ]; do
        Log "Removing old ${1%%[[:space:]]*} settings."
        sed -i "/^${1%%[[:space:]]*}/d" ${KDUMP_CONFIG}
        Log "Adding new '$1'."
        echo "$1" >>"${KDUMP_CONFIG}"
        shift
    done

    RhtsSubmit "${KDUMP_CONFIG}"
}

AppendSysconfig()
{
    Log "Modifying ${KDUMP_SYS_CONFIG}"

    local KEY=$1
    local ACTION=${2,,}
    local VALUE1=$3
    local VALUE2=$4

    if [ -z "$KEY" ] || [ -z "$ACTION" ]; then
        Error "Missing KEY or ACTION"
        return 1
    elif ! grep -E --quiet " add | remove | replace | override " <<< " $ACTION "; then
        Error "Invalid action: $ACTION"
        return 1
    elif [ "$ACTION" = "add" ] && [ -z "$VALUE1" ]; then
        Error "Missing value for adding."
        return 1
    elif [ "$ACTION" = "replace" ] && [ -z "$VALUE2" ]; then
        Error "Missing new_value for replacing."
        return 1
    elif ! grep --quiet "^$KEY=\"" "${KDUMP_SYS_CONFIG}"; then
        # If no such entry in KDUMP_SYS_CONFIG
        # Take no action if $ACTION is 'revmove' ot 'replace'
        # Otherwise, process the sysconfig as ACTION=override
        if grep -E --quiet " remove | replace " <<< " $ACTION "; then
            Log "Sysconfig has no entry with KEY: $KEY. Skip editing."
            RhtsSubmit "${KDUMP_SYS_CONFIG}"
            sync;sync;sync
            return 0
        else
            ACTION=override
        fi
    fi

    local kdump_sys_config_tmp="${KDUMP_SYS_CONFIG}.tmp"
    \cp "${KDUMP_SYS_CONFIG}" "${kdump_sys_config_tmp}"

    # Note: When KEY is "KDUMP_COMMANDLINE", ACTION add/remove/replace is actually
    # manipulating the value of current kernel cmdline and assign
    # it to KDUMP_COMMANDLINE.
    # if there is no value set to KDUMP_COMMANDLINE, assign current kernel cmdline
    # to it for later string manipluation.
    if [ "$KEY" == "KDUMP_COMMANDLINE" ] && \
        grep --quiet "^$KEY=[\ \"]*$" "${kdump_sys_config_tmp}"; then

        sed -i "/^KDUMP_COMMANDLINE=\"/d" "${kdump_sys_config_tmp}"
        echo "KDUMP_COMMANDLINE=\"$(cat /proc/cmdline)\"" >> "${kdump_sys_config_tmp}"
    fi

    case $ACTION in
        add)
            # Check if the key already has a value on it, then append " $VALUE1" to the
            # original value.
            Log "Add '$VALUE1' to '$KEY'"
            if grep -q "^$KEY=[\ \"]*$" "${kdump_sys_config_tmp}"; then
                sed -i /^"$KEY="/d "${kdump_sys_config_tmp}"
                echo "$KEY=\"$VALUE1\"" >> "${kdump_sys_config_tmp}"
            else
                sed -i "/^$KEY=/s/\"/\"$VALUE1 /" "${kdump_sys_config_tmp}"
            fi
            ;;
        remove)
            Log "Remove '$VALUE1' from '$KEY'"
            sed -i  "/^$KEY=/s/$VALUE1//g" "${kdump_sys_config_tmp}"
            ;;
        replace)
            Log "Replace '$VALUE1' with '$VALUE2' for '$KEY'"
            sed -i  "/^$KEY=/s/$VALUE1/$VALUE2/g" "${kdump_sys_config_tmp}"
            ;;
        override)
            Log "Set '$VALUE1' to '$KEY'"
            sed -i "/^$KEY=\"/d" "${kdump_sys_config_tmp}"
            echo "$KEY=\"$VALUE1\"" >> "${kdump_sys_config_tmp}"
            ;;
        *)
            Error "Invalid action '${ACTION}' for editing kdump sysconfig."
            false
            ;;
    esac

    [ $? -ne 0 ] && {
        Error "Failed to edit kdump sysconfig"
        rm -f "${kdump_sys_config_tmp}"
        return 1
    }

    \mv "${kdump_sys_config_tmp}" "${KDUMP_SYS_CONFIG}"
    RhtsSubmit "${KDUMP_SYS_CONFIG}"
    sync;sync;sync
    return 0
}

# Check kdump status
# no error handling
CheckKdumpStatus()
{
    if CommandExists kdumpctl ; then
        LogRun "kdumpctl status"
    elif CommandExists systemctl; then
        LogRun "systemctl status kdump --no-pager"
    else
        LogRun "service kdump status --no-pager"
    fi
}

# This function is to return the path of kernel initrd which will be used in kdump kernel.
GetKdumprd()
{
    local current_version kdumprd
    current_version="vmlinuz-$(uname -r)"

    # if fadump is enabled,kdump kernel will always use the system initrd image.
    # if it is debug system:
    # (1). if the same version of non-debug kernel exists,the kdump kernel will use non-debug kernel for kdump.
    # (2). if the same version of non-debug kernel doesn't exist,the kdump kernel will still use the current debug kernel for kdump.
    # if the system is non-debug kernel,kdump kernel will use this current non-debug kernel for kdump.
    if grep -q -e "fadump=on" -e "fadump=nocma" < /proc/cmdline; then
        kdumprd=${INITRD_IMG_PATH}
    elif $IS_DB && [ -a "$K_BOOT/${current_version%[+-]debug}" ]; then
        kdumprd="${INITRD_KDUMP_IMG_PATH/[+-]debugkdump.img/kdump.img}"
    else
        kdumprd=${INITRD_KDUMP_IMG_PATH}
    fi

    echo $kdumprd
}


ReportKdumprd()
{
    # Get the kdump initramfs img path
    kdumprd=$(GetKdumprd)

    Log "Reporting kdump initramfs image at: $kdumprd"
    if [ -f "${kdumprd}" ]; then
        RhtsSubmit "${kdumprd}"
    else
        Error 'No Kdump initrafms generated!'
    fi

    sync
}

RestartKdump()
{
    local kdumprd=""
    local retval=0

    Log "Restarting Kdump service"
    # TODO: some ppc64 has wrong timestamp, this is a workaround for rhel6
    # BZ: 816831
    touch "${KDUMP_CONFIG}"
    LogRun "ls -l ${K_BOOT}/${INITRD_KDUMP_PREFIX}*kdump.img"
    LogRun "rm -f ${K_BOOT}/${INITRD_KDUMP_PREFIX}*kdump.img"
    LogRun "ls -l ${K_BOOT}/${INITRD_KDUMP_PREFIX}*kdump.img 2>/dev/null"

    local log_file=/tmp/kdump_restart.log
    rm -f ${log_file}

    if $IS_RHEL5 || $IS_RHEL6; then
        LogRun "service kdump restart > ${log_file} 2>&1"
    else
        LogRun "kdumpctl restart > ${log_file} 2>&1"
    fi
    cat ${log_file}
    CheckKdumpStatus
    retval=$?

    if [ "$retval" -ne 0 ]; then
        # Bug 1754815 Kdump: Building kdump initramfs img may fail with
        # 'Write failed because Bad file descriptor' occasionally
        # Try one more time.
        if grep -qi "Write failed because Bad file descriptor" ${log_file} && \
        grep -qi "failed to make kdump initrd" ${log_file}; then
            Warn "Kdump failed to make kdump initrd: Write failed because Bad file descriptor (BZ#1754815)."
            Log "Try#2: Restarting kdump service again"
            LogRun "kdumpctl restart > ${log_file} 2>&1"
            cat ${log_file}
        # The kdump dump path priviledge may be temporarily changed on a remote vmcore server
        # Try one more time see if the file priviledge gets fixed on the remote server.
        elif grep -qi "Could not create temporary directory" ${log_file}; then
            Warn "Kdump restart failed: No write permission on dump path on"
            Log "Try#2: Restarting kdump service after 1 min"
            sleep 60
            LogRun "kdumpctl restart > ${log_file} 2>&1"
            cat ${log_file}
        fi
        CheckKdumpStatus
        retval=$?
    fi
    [ "$retval" -ne 0 ] && MajorError "Restarting kdump failed"

    sync; sync; sleep 10
    # It may report "No kdump initial ramdisk found.[WARNING]" in rhel6
    local skip_pat="No kdump initial ramdisk found|Warning: There might not be enough space to save a vmcore|Warning no default label"
    skip_pat+="|WARNING: Option 'default' was renamed 'failure_action' and will be removed in the future"
    if grep -q '^\s*raw' ${KDUMP_CONFIG}; then
        # If raw target. skip following warning as well
        skip_pat+="|signature on.*data loss is expected"
    fi

    if grep -v -E "$skip_pat" ${log_file} |  grep -i -E "can't|error|warn|miss|No such file or directory|command not found";  then
        Warn 'Restarting kdump reported above warn/error message'
    fi
    sync;
    [ "$NOKDUMPRD" != true ] && ReportKdumprd
}


GetDumpfs()
{
    local path

    # If we have already supplied a path value, we'll use it here.
    # Otherwise, we will not know which partition to use during Kdump.
    if [ -n "$1" ]; then
        path=$1
    elif [ -f "${K_PATH}" ]; then
        path=$(cat "${K_PATH}")
    else
        path="${K_DEFAULT_PATH}"
    fi

    # Handle target directory is on a separated partition.
    fsline=$(mount | grep " ${path} ")

    # FIXME: parent directories on a separated partion.

    # Check rootfs.
    if [ -z "${fsline}" ]; then
        fsline=$(mount | grep ' / ')
    else
        # If /var/crash is on a separate partition, then VMCore will be
        # found at /var/crash/var/crash.
        echo "${path}${path}" >"${K_PATH}"
    fi

    if $IS_RHEL5 || $IS_RHEL6 ; then
        if [[ $(echo "${fsline}" | awk '{print $5}') != ext[34] ]]; then
            FatalError "Target directory is not on an EXT3/EXT4 partition."
        fi
    fi

    target=$(echo "${fsline}" | awk '{print $1}')
}

# ---------------- Advanced Configurations for Kdump Service  ------------------------ #

RESTART_KDUMP=${RESTART_KDUMP:-"true"}

# @usage: LabelFS <fstype> <dev> <mntpnt> <label>
# @description: add label to specified fs
# @param1: fstype
# @param2: device
# @param3: mount point
# @param4: label
LabelFS()
{
    local fstype="$1"
    local dev="$2"
    local mntpnt="$3"
    local label="$4"

    case $fstype in
        xfs)
            umount $dev &&
            xfs_admin -L $label $dev &&
            mount $dev $mntpnt
            ;;
        ext[234])
            e2label $dev $label
            ;;
        btrfs)
            umount $dev &&
            btrfs filesystem label $dev $label &&
            mount $dev $mntpnt
            ;;
        *)
            false
            ;;
    esac

    if [ $? -ne 0 ]; then
        FatalError "Failed to label $fstype with $label on $dev"
    fi
}


# @usage: ConfigFS
# @description: config fs dump target to kdump
# KPATH: The relative path on the dump target where the vmcore will be saved to
# OPTOIN: The way to specify dump target: uuid/softlink/label/devname. Default 'devname'
# LABEL: Provide label name if OPTION='label'. Default label name: label-kdump
# RAW: Whether it's a raw target. yes/no. Default is 'no'
# RESTART_KDUMP: Whether restart kdump service after updating kdump config. Default 'true'
ConfigFS()
{
    local dev=""
    local fstype=""
    local target=""

    if [ "$RAW" == "true" ] && [ -f "${K_RAW}" ]; then
        # if $K_RAW exists, use the dev stored in $K_RAW as dump target
        dev=$(cut -d"," -f1 ${K_RAW})
    else
        dev=$(findmnt -kcno SOURCE $MP)
        fstype=$(findmnt -kcno FSTYPE $MP)
    fi

    export LABEL
    case ${OPTION,,} in
        uuid)
            # some partitions have both UUID= and PARTUUID=
            # we only want UUID=
            target=$(blkid $dev -o export -c /dev/null | grep '\<UUID=')
            ;;
        label)
            target=$(blkid $dev -o export -c /dev/null | grep LABEL=)

            # only label a fs if it hasn't label'd yet.
            if [ -z "$target" ]; then
                LabelFS "$fstype" "$dev" "$MP" "$LABEL"
                target=$(blkid $dev -o export -c /dev/null | grep LABEL=)
            fi
            ;;
        softlink)
            ln -s "$dev" "$dev-softlink"
            target=$dev-softlink
            ;;
        *)
            # on s390x. dev path like /dev/dasda may change at each boot.
            # use /dev/disk/by-path/ccw-0.0.0121-part1 instead.
            if [ "$K_ARCH" = "s390x" ] && echo "$dev" | grep -vq "/dev/mapper"; then
                dev=$(udevadm info -q symlink --name $dev -r | sed 's/ /\n/g' | grep 'by-path' | grep 'part[0-9]\+')
            fi
            target=$dev
            ;;
    esac

    if [ "$RAW" == "true" ] && [ -n "$target" ]; then
        AppendConfig "raw $target"

        # If using makedumpfile as core_collector, it has to be used with option -F.
        if grep -q -E "^\s*core_collector\s+makedumpfile" "${KDUMP_CONFIG}"; then
            AppendConfig "core_collector makedumpfile -F -d 31"
        fi
        echo "$dev,$fstype,$MP" > ${K_RAW}

        # Avoid fsck in next boot since it's a raw device
        local temp_mp="${MP////\\/}"
        sed -i "/[ \t]${temp_mp}[ \t]/d" ${FSTAB_FILE}
        RhtsSubmit ${FSTAB_FILE}

    elif [ -n "$fstype" ] && [ -n "$target" ]; then
        AppendConfig "$fstype $target" "path $KPATH"
        mkdir -p $MP/$KPATH
        # tell /kdump/analysa-crash where to find vmcore
        echo "${MP%/}$KPATH" >${K_PATH}
    else
        FatalError "Null dump device/UUID/LABEL or type wrong (fstype/raw)."
    fi

    if [ "${RESTART_KDUMP,,}" = "true" ]; then
        RestartKdump
    fi
}

# @usage: ConfigFilter
# @description: config makedumpfile options to core_collector
# TESTARGS: The makedumpfile options will be set to core_collector. Default values are:
#           rhel7/8/9: -l --message-level 7 -d 31
#           otherwise: -c --message-level 7 -d 31
# RESTART_KDUMP: Whether restart kdump service after updating kdump config. Default 'true'
ConfigFilter()
{
    # makedumpfile options
    if [ -n "${TESTARGS}" ]; then
        opt="${TESTARGS}"
    elif $IS_RHEL5 || $IS_RHEL6 ; then
        opt="-c --message-level 7 -d 31"
    else
        opt="-l --message-level 7 -d 31"
    fi

    if [ -z "${TESTARGS}" ] && grep -qE '^(ssh|raw)' ${KDUMP_CONFIG}; then
        opt+=" -F"
    fi

    AppendConfig "core_collector makedumpfile ${opt}"

    if [ "${RESTART_KDUMP,,}" = "true" ]; then
        RestartKdump
    fi
}

# @usage: ConfigAny
# @description: Add a kdump option line
# TESTARGS: The option line will added to kdump config
# RESTART_KDUMP: Whether restart kdump service after updating kdump config. Default 'true'
ConfigAny()
{
    local config_opt key values

    config_opt=${1:-"$TESTARGS"}
    config_opt="$(Chomp "${config_opt}")"

    [ -z "${config_opt}" ] && {
        # Force restarting kdump service and exit
        RestartKdump
        RhtsSubmit "${KDUMP_CONFIG}"
        return 0
    }

    key="${config_opt%%[[:space:]]*}"
    values=$(sed "s/^${key}[[:space:]]\+//" <<< "${config_opt}")

    CheckConfig
    AppendConfig "${config_opt}"

    if [ "$values" == '/bin/kdump-pre.sh' ] || [ "$values" == '/bin/kdump-post.sh' ]; then
        sh gen-helper-script
    fi

    [ "${RESTART_KDUMP,,}" = "false" ] && return 0

    RestartKdump

    lsinitrd ${INITRD_KDUMP_IMG_PATH} > lsinitrd.log

    RhtsSubmit lsinitrd.log    # debug use

    # Verify if kdump_pre, kdump_post, extra_bins or extra_modules
    # are packed into kdump initramfs img correctly

    # Since RHEL8 (kexec-tools-2.0.17-16.el8), files such as post/pre scripts and binaries
    # are squashed into <initramfs>/squash/root.img. So the post/pre script and
    # binaries inclusion cannot be verified by running lsinitrd. Skip it for now.
    ( $IS_RHEL8 || $IS_RHEL9 ) && return 0

    if [ "$key" = kdump_post ] || [ "$key" = kdump_pre ]; then
        local file
        file=$(awk '{print $2}' <<< "$config_opt")
        [ -f "$file" ] && RhtsSubmit "$file"
    fi

    case "$key" in
        kdump_post|kdump_pre|extra_bins|extra_modules)
            for val in $values; do
                grep -q "${val##*/}" lsinitrd.log ||
                Error "'${val}' is not included in kdump image!"
            done
            ;;
        *)
            return 0
            ;;
    esac
}


# ---------- Trigger System Panic ------------ #

PANIC_VMCORE_CHECK=${PANIC_VMCORE_CHECK:-"true"}


# Wrapper of system crash tests consisting of
#    - system setup (func_config)
#    - system panic (func_panic)
#    - validation after system is back (func_validation)
SystemCrashTest(){
    local func_panic=${1:-"TriggerSysrqC"}
    local func_config=${2:-""}
    local func_validation=${3:-""}

    if [ ! -f "${K_REBOOT}" ]; then
        Log "Prepare reboot"
        PrepareReboot

        Log "Check kdump status before triggering panic"
        CheckKdumpStatus

        # ----- Configure system ----------------
        eval MultihostStage config ${func_config}
        # Upload configurations
        RhtsSubmit "${KDUMP_CONFIG}"
        RhtsSubmit "${KDUMP_SYS_CONFIG}"

        if [ "${CHECK_INITRD_REBUILD,,}" = true ]; then
            ls -l --full-time "${INITRD_KDUMP_IMG_PATH}" > "${K_TESTAREA}/KDUMP_INITRD_TIME_OLD"
            sync
            sleep 5
        fi

        # ----- Trigger panic ----------------
        Log "-------------"
        Log "Trigger Panic"
        Log "-------------"
        Report 'boot-2nd-kernel'
        touch "${K_REBOOT}"; sync; sync; sync;
        ${func_panic}
        # ------------------------------------

        sleep 60
        Error "Failed to trigger system panic"
        rm -f "${K_REBOOT}"
   else
        eval MultihostStage validation ${func_validation}
        rm -f "${K_REBOOT}"

        if [ "${CHECK_INITRD_REBUILD,,}" = true ]; then
            Log "[CHECK_INITRD_REBUILD=true] Check if kdump img is rebuilt unexpectedly"
            CheckKdumpStatus  # Wait kdump service to be fully started in case kdumpctl rebuild.
            ls -l --full-time "${INITRD_KDUMP_IMG_PATH}" > "${K_TESTAREA}/KDUMP_INITRD_TIME_NEW"

            # Compare the timestamp of kdump initramfs img before/after system reboot.
            Log "Compare timestamp of kdump imgs before/after system reboot."
            diff "${K_TESTAREA}/KDUMP_INITRD_TIME_OLD" "${K_TESTAREA}/KDUMP_INITRD_TIME_NEW" || {
                Error "Unexpected kdump initramfs img change. Please read messages log for details"
                cat "${K_TESTAREA}/KDUMP_INITRD_TIME_OLD"
                cat "${K_TESTAREA}/KDUMP_INITRD_TIME_NEW"

                # Submit kdump logs
                if CommandExists journalctl ; then
                    journalctl -u kdump > "${K_TESTAREA}/kdump.messages.log"
                    sync
                    RhtsSubmit "${K_TESTAREA}/kdump.messages.log"
                else
                    RhtsSubmit /var/log/messages
                fi
                rm -f "${K_TESTAREA}/KDUMP_INITRD_TIME_OLD"
                rm -f "${K_TESTAREA}/KDUMP_INITRD_TIME_NEW"

            }
        fi

        [ "${PANIC_VMCORE_CHECK,,}" = true ] && {
            grep ^raw ${KDUMP_CONFIG} && sleep 60 # Wait raw dump vmcore to be copied to rootfs
            Log "--------------------------------------------------"
            Log "[PANIC_VMCORE_CHECK=true] Check if vmcore is saved"
            Log "--------------------------------------------------"
            GetCorePath
            report_result "check-vmcore" PASS 0
        }

    fi
}

TriggerSysrqC(){
        # Check if sysrq operation is enabled for SYSRQ_ENABLE_DUMP
        # in include/linux/sysrq.h
        # /* 0x0001 is reserved for enable everything */
        # define SYSRQ_ENABLE_DUMP  0x0008
        # In RHEL6, it's set to 0 by default.

        # local sysrq_value
        # sysrq_value=$(cat /proc/sys/kernel/sysrq)
        # [ "$sysrq_value" -eq 0 ] && Warn "kernel.sysrq is set to 0 which is unexpected."

        LogRun "cat /proc/sys/kernel/sysrq"

        # Removed the setting of kernel.sysrq as Bug 1684348 is fixed
        # on kernel-4.18.0-76.el8
        # if [ "$sysrq_value" -ne 1 ] && [ "$sysrq_value" -ne 8 ]; then
        #     echo 8 > /proc/sys/kernel/sysrq
        # fi

        # Trigger panic
        sync;sync;sync; sleep 10
        echo c >/proc/sysrq-trigger
        # Should stop here.
}

TriggerSysrqCWithBPF(){

        rpm -q --quiet bcc || InstallPackages bcc

        #Log "Run biotop 20 mins at background"
        Log "Run slabratetop 20 mins at background"
        # to workaround Bug 1665024 - bcc doesn't work when ARCH env is set
        local temp_arch=$ARCH
        unset ARCH
        Log "# /usr/share/bcc/tools/slabratetop -C 20 60 &"
        /usr/share/bcc/tools/slabratetop -C 20 60 &
        ARCH=$temp_arch

        #Log "Wait 10 mins for biotop to be fully up"
        Log "Wait 10 mins for slabratetop to be fully up"
        sleep 600

        TriggerSysrqC
}
