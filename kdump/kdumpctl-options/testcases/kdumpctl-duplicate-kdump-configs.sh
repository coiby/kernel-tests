#!/bin/sh

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Test Bug 1862884 - Detect duplicated config error in
#                kdump.conf to prevent misuse of core_collector
#   Author: Xiaoying Yan <yiyan@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1862884 - Detect duplicated config error in kdump.conf to prevent
#               misuse of core_collector
# Fixed in RHEL-8.4 kexec-tools-2.0.20-46
CheckResult(){
    local conf=$1
    local restart_log=$2

    Log "Restart Kdump Service"
    kdumpctl restart | tee ${restart_log} 2>&1
    local retval=${PIPESTATUS[0]}

    cp -f ${KDUMP_CONFIG} ${conf}
    RhtsSubmit "${kdump_conf}"
    RhtsSubmit "${restart_log}"
    rm -f ${conf}

    if [ "$retval" -eq 0 ] || ! grep -qi 'Duplicated' "${restart_log}"; then
        Log "Pass. Kdump failed to start and reported error: duplicated config."
    else
        Error "Kdump didn't report duplicated config as expected. Check $restart_log for details."
    fi
}

DuplicateConfigsCheck() {
    CheckSkipTest kexec-tools 2.0.20-46 && return

    local kdump_restart_log=kdump_restart_dup_path.log
    local kdump_conf=kdump_config_dup_path

    # Backup the kdump.conf
    [ -f "./kdump.conf.bk" ] || \cp "${KDUMP_CONFIG}" ./kdump.conf.bk

    # Test1: Duplicate 'path'
    Log "Test1: Create kdump config with duplicate paths"
    echo 'path /var/test' >> ${KDUMP_CONFIG}
    echo 'path /var/test' >> ${KDUMP_CONFIG}
    sync; sleep 5 # Wait to make sure kdump config is saved to fs
    # Restart kdump service and check error message
    CheckResult "${kdump_conf}" "${kdump_restart_log}"

    # Test2: Duplicate 'core_collector'
    Log "Test2: Create kdump config with duplicate core_collector."
    kdump_restart_log=/tmp/kdump_restart_dup_core_collector.log
    kdump_conf=/tmp/kdump_config_core_collector
    echo 'core_collector cp' >> ${KDUMP_CONFIG}
    sed -i '/path \/var\/test/d' ${KDUMP_CONFIG}
    sync; sleep 5 # Wait to make sure kdump config is saved to fs
    # Restart kdump service and check error message
    CheckResult "${kdump_conf}" "${kdump_restart_log}"

    # Test cleanup
    Log "Cleanup: Restore Kdump config and restart Kdump service"
    mv -f ./kdump.conf.bk "${KDUMP_CONFIG}"
    RestartKdump
}

MultihostStage "$(basename "${0%.*}")" DuplicateConfigsCheck
