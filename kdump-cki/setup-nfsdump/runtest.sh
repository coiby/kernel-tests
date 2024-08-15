#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

REBOOT="./KDUMP-REBOOT"
SUBMITTER=${SUBMITTER%@*}
MNT_POINT=${MNT_POINT:-"/var/crash"}

mkdir -vp $MNT_POINT

if [[ -n "$SUB_DIR" ]]; then
    CRASH_PATH=$MNT_POINT/$SUB_DIR
else
    SUB_DIR=${SUBMITTER:-cki}/$(uname -r)/${RSTRNT_JOBID:-nojobid}/${HOSTNAME:-nohostname}
    CRASH_PATH=$MNT_POINT/$SUB_DIR
fi

rpm -q --quiet nfs-utils || InstallPackages nfs-utils

function CheckPackage()
{
    # Install and upgrade the kdump main package if needed
    PrepareKdump || {
        echo "Install $MAIN_RPM_PACKAGE Failed!" | tee -a "$OUTPUTFILE"
        rstrnt-report-result "$RSTRNT_TASKNAME/CheckPackage" "FAIL" "1"
        return 1
    }
    LogRun "rpm -q kdump-utils makedumpfile kexec-tools dracut systemd selinux-policy"
    return 0
}

function CheckServer()
{
    if [[ -z "$NFSSERVER" ]]; then
        cki_abort_task "FAIL: NFSSERVER variable is not set"
    fi

    if [[ -z "$VMCOREPATH" ]]; then
        cki_abort_task "FAIL: VMCOREPATH variable is not set"
    fi

    if [[ -z "$WEBSERVERBASEURL" ]]; then
        cki_abort_task "FAIL: WEBSERVERBASEURL variable is not set"
    fi

    echo | tee -a "$OUTPUTFILE"
    Log "------------------------------------------------"
    Log "The Specified NFS Server: $NFSSERVER"
    Log "The Specified VMCOREPATH: $VMCOREPATH"
    Log "The Specified WEBSERVERBASEURL: $WEBSERVERBASEURL"
    Log "------------------------------------------------"

    if [[ "$NFSSERVER" =~ ^[[:space:]]*$ || "$VMCOREPATH" =~ ^[[:space:]]*$ ]]; then
        Error "\$NFSSERVER or \$VMCOREPATH invalid!"
        rstrnt-report-result "$RSTRNT_TASKNAME/CheckServer" "FAIL" "1"
    fi
}

function UpdateKdumpConfig()
{
    cp /etc/kdump.conf /etc/kdump.conf.orig
    echo > /etc/kdump.conf

    if [ "$(uname -r|awk -F. '{print $1}')" -ge 3 ]; then
        echo "nfs $NFSSERVER:$VMCOREPATH" >> /etc/kdump.conf
    else
        echo "net $NFSSERVER:$VMCOREPATH" >> /etc/kdump.conf
        echo "link_delay 60" >> /etc/kdump.conf
    fi

    # use zlib compression by default
    # use lzo compression on RHEL7 and newer
    # task parameter COMPRESSION overrides the defaults
    # task parameter NO_COMPRESS overrides all

    ALGO="-c"
    if [[ "$RELEASE" -ge 7 ]]; then
        ALGO="-l"
    fi

    if [ "$COMPRESSION" = "zlib" ]; then
        ALGO="-c"
    elif [ "$COMPRESSION" = "lzo" ]; then
        ALGO="-l"
    fi

    if [[ "$NO_COMPRESS" -ne 0 ]]; then
        echo "core_collector makedumpfile -E -d 31" >> /etc/kdump.conf
    else
        echo "core_collector makedumpfile $ALGO -d 31" >> /etc/kdump.conf
    fi

    echo "path /$SUB_DIR" >> /etc/kdump.conf
    # kdump failed to start and drop to shell on s390x, aborting tests
    # See rhel9 bug1931284, rhel8 bug1941106. Use 'reboot' instead of 'shell'
    # for workaround.
    #echo "default shell" >> /etc/kdump.conf
    echo "default reboot" >> /etc/kdump.conf


    # Setup flag files so tests run afterwards know where vmcore is saved to.
    echo "${VMCOREPATH}" > "${K_NFS}"
    echo "/$SUB_DIR" > "${K_PATH}"

    # debug use
    cki_upload_log_file /etc/kdump.conf

    # Reliably pass around where the core dumps are accessible
    if [ -n "${WEBSERVERBASEURL}" ]; then
        echo "${WEBSERVERBASEURL}/${SUB_DIR}" >/tmp/coredump.url
        cki_upload_log_file /tmp/coredump.url
    fi
}

# This function mainly works for upstream kernel
function SetImageType()
{
    # The installed upstream kernel default is debug kernel.
    if [ -f "/boot/vmlinuz" ]; then
        IMAGETYPE="vmlinuz"
        IS_DB=true
        IS_UPSTREAM_LINUX=true
    elif [ -f "/boot/vmlinux" ]; then
        IMAGETYPE="vmlinux"
        NO_COMPRESS=1
        IS_DB=true
        IS_UPSTREAM_LINUX=true
    elif [ -f "/boot/bzImage" ]; then
        IMAGETYPE="bzImage"
        IS_DB=true
        IS_UPSTREAM_LINUX=true
    elif [ -f "/boot/vmlinuz.gz" ]; then
        IMAGETYPE="vmlinuz.gz"
        IS_DB=true
        IS_UPSTREAM_LINUX=true
    elif [ -f "/boot/image" ]; then
        IMAGETYPE="image"
        IS_DB=true
        IS_UPSTREAM_LINUX=true
    fi

    if [ -n "$IMAGETYPE" ]; then
        sed -i "s/KDUMP_IMG\=.*/KDUMP_IMG=\"${IMAGETYPE}\"/"   /etc/sysconfig/kdump
    fi
}

function ReserveMem()
{
    rpm -q --quiet grubby || InstallPackages grubby

    local args=""
    local default=$(/sbin/grubby --default-kernel)

    Log "Prepare crashkernel=xxxM if crash memory is not reserved by default"

    # If fadump is enabled, crashkernel memory reservation can only be observed by checking system logs.
    if grep -q "fadump=on" /proc/cmdline ; then
        LogRun "journalctl -b | grep \"firmware-assisted dump\" | grep Reserved"
        [ $? -eq 0 ] && return  # crashkernel for fadump is reserved.
        args="crashkernel=384M" # crashkernel for fadump is not reserved. Set the 384M.
    fi

    LogRun "cat /sys/kernel/kexec_crash_size"

    # Assign more crashkernel than crashkernel=auto as it may require more in net dump.
    local kernel_main_ver="$(uname -r | awk -F. '{print $1}')"
    local kernel_main_rel="$(uname -r | awk -F '-' '{split($2,rel,"."); print rel[1]}')"
    kernel_main_rel=${kernel_main_rel:-0}

    if [[ -n "$CRASHSIZE" ]]; then
        args="crashkernel=$CRASHSIZE"
    elif [ "${kernel_main_ver}" -ge 5 ]; then
        args="crashkernel=1G-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        [[ "true" = "$IS_DB" ]] && args="crashkernel=1G-2G:384M,2G-3G:512M,3G-4G:768M,4G-16G:1G,16G-64G:2G,64G-128G:2G,128G-:4G"
        [[ "true" = "$IS_UPSTREAM_LINUX" ]] && [ "${IMAGETYPE}" = "vmlinux" ] && args="crashkernel=1G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        [ "${ARCH}" = aarch64 ] && {
            args="crashkernel=768M"
            # It may fail to reserve memory as if low memory is not big enough. So here
            # specifying ',high' explicity to reserve memory in high memory.
            # But "crashkernel=x,high" is only supported since RHEL-9.1:
            # Bug 2091852 - arm64: add crashkernel=x,high support on arm64 (kernel-5.14.0-122.el9)
            if [ "${kernel_main_rel}" -ge "122" ]; then args="crashkernel=768M,high"; fi
        }
    elif [ "${kernel_main_ver}" -ge 4 ]; then
        args="crashkernel=1G-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        [[ "true" = "$IS_DB" ]] && args="crashkernel=1G-2G:384M,2G-3G:512M,3G-4G:768M,4G-16G:1G,16G-64G:2G,64G-128G:2G,128G-:4G"
        [[ "true" = "$IS_UPSTREAM_LINUX" ]] && [ "${IMAGETYPE}" = "vmlinux" ] && args="crashkernel=1G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        [ "${ARCH}" = aarch64 ] && args="crashkernel=768M"
    elif [ "${kernel_main_ver}" -ge 3 ]; then
        args="crashkernel=0M-4G:384M,4G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        [[ "true" = "$IS_UPSTREAM_LINUX" ]] && [ "${IMAGETYPE}" = "vmlinux" ] && args="crashkernel=1G-16G:512M,16G-64G:1G,64G-128G:2G,128G-:4G"
        [ "${ARCH}" = aarch64 ] && args="crashkernel=768M"
    elif expr "$(uname -r)" : '2\.6\.32.*'; then
        if [ "${ARCH}" = "ppc64" ]; then
            args="crashkernel=256M@34M"
        elif [ "${ARCH}" = "s390x" ]; then
            args="crashkernel=128M"
        else
            args="crashkernel=128M"
        fi
        [[ "true" = "$IS_DB" ]] && args="crashkernel=256M"
    elif expr "$(uname -r)" : '2\.6\.18.*'; then
        if [ "${ARCH}" = "ppc64" ]; then
            args="crashkernel=256M@32M xmon=off"
        elif [ "${ARCH}" = "ia64" ]; then
            args="crashkernel=512M@256M"
        else
            args="crashkernel=128M@16M"
            [[ "true" = "$IS_RT" ]] && args="crashkernel=128M"
        fi
    fi

    if [ -z "$args" ]; then
        Log "No need to update kernel options"
    else
        Log "Update kernel options"
        UpdateKernelOptions "${args}"
        if [ $? -ne 0 ]; then
            Error "Failed to update boot options"
            rstrnt-report-result "$RSTRNT_TASKNAME/bootloader" "FAIL" "1"
        fi
    fi

    # Extra step for s390x
    [ "${ARCH}" = "s390x" ] && zipl
}


UpdateKdumpSysconfig()
{
    # Set KDUMP_FILE_LOAD to off if option presents
    # Otherwise it will require the kernel to be signed with a certified key
    if grep -i KDUMP_FILE_LOAD "${KDUMP_SYS_CONFIG}" ; then
        AppendSysconfig KDUMP_FILE_LOAD override "off"
    fi
}

# ---------- Start Test -------------
# hack /usr/bin/kdumpctl: add 'chmod a+r corefile'
sed 's;mv $coredir/vmcore-incomplete $coredir/vmcore;&\nchmod a+r $coredir/*;' /usr/bin/kdumpctl -i

if [ ! -f "$REBOOT" ]; then
    Log "----------------------------------"
    Log "$(date)"
    Log "----------------------------------"
    Log "kernel: $(uname -r)"
    Log "----------------------------------"

    SetImageType
    CheckPackage || exit 1
    ReserveMem
    Log "To be Rebooting ..."
    touch "$REBOOT"

    rstrnt-report-result "$RSTRNT_TASKNAME/rstrnt-reboot" "PASS" "0"
    sync && rstrnt-reboot

# Already reboot with above crashkernel
else
    Log "----------------------------"
    Log "$(date)"
    Log "----------------------------"
    Log "kernel: $(uname -r)"
    Log "----------------------------"

    if [[ "${RSTRNT_REBOOTCOUNT}" -ge 2 ]]; then
        rstrnt-report-result "$RSTRNT_TASKNAME/rstrnt-reboot" "fail" "0"
        MajorError "Unexpected reboot! REBOOTCOUNT is ${REBOOTCOUNT}"
    fi

    rm -f "$REBOOT"

    # Here need set NO_COMPRESS value. So call this function SetImageType
    SetImageType
    CheckServer
    UpdateKdumpConfig
    UpdateKdumpSysconfig

    # To verify if kdump is started with the crashkernel
    Log "Enable and Restart kdump service"
    LogRun "cat /sys/kernel/kexec_crash_size"

    if [ "$(uname -r|awk -F. '{print $1}')" -ge 3 ]; then

        systemctl enable kdump.service > /dev/null 2>&1
        Log "Update nfs mount in /etc/fstab"
        echo "$NFSSERVER:$VMCOREPATH $MNT_POINT nfs defaults 0 0" >> /etc/fstab
        mount $NFSSERVER:$VMCOREPATH $MNT_POINT
        mkdir -p $CRASH_PATH
        cki_upload_log_file /etc/fstab

        # Run kdumpctl status to make sure the kdump.img built at first boot is
        # complete. This is to avoid cases like
        #     kdumpctl restart
        #     Another app is currently holding the kdump lock; waiting for it to exit...
        # If kdump.img built at first boot is done after updating kdump.conf, it
        # will not rebuild kdump initramfs image with nfs mount. Because it
        # believes there is no kdump config change since 'last' kdump img built.

        kdumpctl status > /dev/null 2>&1
        rm -f /boot/initramfs-*kdump.img
        LogRun "kdumpctl restart"
        LogRun "kdumpctl status"
    else
        chkconfig kdump on > /dev/null 2>&1

        kdumpctl status > /dev/null 2>&1
        rm -f /boot/initrd-*kdump.img
        LogRun "service kdump restart"
        LogRun "service kdump status --no-pager"
    fi

    if [ $? -eq 0 ]; then
        Log "Pass"
        sleep 30
        rstrnt-report-result "$RSTRNT_TASKNAME" "PASS" "0"
    else
        Error "Kdump servie is not operational"
        Error "Fail"
        rstrnt-report-result "$RSTRNT_TASKNAME" "FAIL" "1"
    fi
fi
