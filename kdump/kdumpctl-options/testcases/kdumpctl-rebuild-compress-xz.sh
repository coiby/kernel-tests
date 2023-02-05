#!/bin/sh

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Test Bug 2004000 - [RHEL-8.5][fence kdump] kdump kernel failed with default crashkernel size that "/bin/sh: error while loading shared libraries: libtinfo.so.6: cannot open shared object file#   : No such file or directory "
#   Author: Xiaoying Yan <yiyan@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 2004000 - [RHEL-8.5][fence kdump] kdump kernel failed with default
#               crashkernel size that "/bin/sh: error while loading shared
#               libraries: libtinfo.so.6: cannot open shared object
#               file#   : No such file or directory "
# Fixed in RHEL-8.6.0 kexec-tools 2.0.20-68

Check_CompressFormat(){
    if [ "$ALLOW_SKIP" = "true" ]; then
        if [ "$RELEASE" -ge 9 ]; then
            Skip "Skip on RHEL9 and newer releases, as it uses zstd as default to compress initramfs, not xz."
            return
        else
            CheckSkipTest kexec-tools 2.0.20-68 && return
        fi
    fi

    local kdump_mesg_log=compress_xz_kdump_mesg.log
    local retval=0
    CheckKdumpStatus
    [ "$?" -ne 0 ] && Error "Kdump is not operational."

    LogRun "kdumpctl rebuild"
    Log "Check the compress format of initramfs used by dracut."
    if [ "$?" -eq 0 ];then
        LogRun "journalctl -b |grep '/usr/bin/dracut' > ${kdump_mesg_log}"
        RhtsSubmit "${kdump_mesg_log}"
        grep -qi 'compress=xz' ${kdump_mesg_log} || Error "Dracut's squash module should be compressed in xz, but it's not. Check ${kdump_mesg_log} for details"
    else
        Error "Failed to rebuild the crash kernel initramfs."
    fi
}

MultihostStage "$(basename "${0%.*}")" Check_CompressFormat
