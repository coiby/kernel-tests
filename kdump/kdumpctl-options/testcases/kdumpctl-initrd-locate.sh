#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 2006000 - RHEL 8 debug-kernel doesn’t create a vmcore file when it crashes.
# Fixed in kexec-tools-2.0.24-5.el8.
# Bug 2076425 - RHEL 9 debug-kernel doesn’t create a vmcore file when it crashes.
# Fixed in kexec-tools-2.0.24-5.el9.

CheckSkipTest kexec-tools 2.0.24-5 && Report

# Check whether it uses the expected initrd image for kdump
CheckKdumpInitrdPath(){
    local kdumprd
    local kdump_log="/tmp/kdump_file.log"

    # get the path of kernel initrd which will be used in kdump kernel
    kdumprd=$(GetKdumprd)
    if [ ! -s "$kdumprd" ];then
        Error "Can't get the expected initrd image path for kdump kernel."
        return
    fi

    touch ${KDUMP_CONFIG}

    # If the expected initrd image does not exist,needs to rebuild it and then load it.
    LogRun "kdumpctl restart > ${kdump_log} 2>&1"
    local retval=${PIPESTATUS[0]}
    RhtsSubmit ${kdump_log}

    if [ "${retval}" -eq "0" ]; then
        # If the kdump service was restarted successfully,it will print out the path of initrd image info.
        # for example, on stock kernel and disable fadump,after restart kdump service, it will has below info:
        # kdump: Rebuilding /boot/initramfs-$(uname -r)kdump.img
        # check the path of initrd image if it is the expected one.
        LogRun "grep -q "$kdumprd" "${kdump_log}"" || Error "Kexec load the wrong initrd image,the expected one is "$kdumprd", please check the log "${kdump_log}"."
    else
        Error "Failed to restart kdump service."
    fi
}

MultihostStage "$(basename "${0%.*}")" CheckKdumpInitrdPath
