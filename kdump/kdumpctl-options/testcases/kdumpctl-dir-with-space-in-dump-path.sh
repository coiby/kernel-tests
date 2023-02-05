#!/bin/sh

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:  Bug 1986265 - kdumpctl throws error with restorecon if dump location has any dir or file with space in its name
#   Author: Ruowen Qin <ruqin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1986265 - kdumpctl throws error with restorecon if dump location has
#               any dir or file with space in its name
# Fixed in RHEL-8.6 kexec-tools-2.0.20-68
KdumpctlRestart() {
    CheckSkipTest kexec-tools 2.0.20-68 && return

    local vmcore_path="/var/crash"

    if [ -d "${vmcore_path}" ]; then
        # Check if the vmcore path is a mounted remoted file system.
        df -T "${vmcore_path}" | tail -n 1 | awk '{print $2}' | grep -q nfs
        [ $? -eq 0 ] && {
            LogRun "df -T ${vmcore_path}"
            Error "Dump target ${vmcore_path} is a mounted remoted file system"
            Report
        }
    else
        Error "Dump target ${vmcore_path} is not a directory"
        Report
    fi

    CheckConfig

    # backup the kdump.conf
    [ -f "./kdump.conf.bk" ] || \cp -f "${KDUMP_CONFIG}" ./kdump.conf.bk

    # resotre the default kdump.conf
    echo "path ${vmcore_path}" > ${KDUMP_CONFIG}

    [ -e "/var/crash/test dir" ] && rm -rf /var/crash/'test dir'
    Log "Create a test dir with space under dump path: /var/crash/'test dir'"
    LogRun "mkdir /var/crash/'test dir'"
    sync
    sleep 10

    local log_file=/tmp/kdump_space_in_path_restart.log
    LogRun "kdumpctl restart >${log_file} 2>&1"
    cat ${log_file}

    CheckKdumpStatus
    if [ "$?" -ne 0 ] || grep -qi restorecon "${log_file}" ; then
        # Kdump service not started or throw restorecon error. e.g.
        # check if the kdumpctl occurs lstat(///var/crash/test) failed:  No such file or directory
        Error "Kdump service is not started or started with error"
    fi

    Log "Test clean and restore kdump service"
    LogRun "rm -rf /var/crash/'test dir'"
    mv -f ./kdump.conf.bk "${KDUMP_CONFIG}"
    sync
    sleep 10
    RestartKdump
}

MultihostStage "$(basename "${0%.*}")" KdumpctlRestart
