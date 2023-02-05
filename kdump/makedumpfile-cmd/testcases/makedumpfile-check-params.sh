#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

rebuild_log="/tmp/kdump_rebuild.log"


ParamsCheckTest()
{
    local options=$1
    local exp_ret=0
    local act_ret=0
    [[ "${2,,}" =~ fail ]] && exp_ret=1 # Expect a fail result

    echo ""
    Log "Check-params test: $options."
    AppendConfig "${options}";
    sleep 5
    Log "Rebuild Kdump initramfs image"
    kdumpctl rebuild > ${rebuild_log} 2>&1
    act_ret=${PIPESTATUS[0]}

    if [ "${exp_ret}" -ne "${act_ret}" ] || ([ "${exp_ret}" -eq 1 ] && ! grep -q "makedumpfile parameter check failed" ${rebuild_log}); then
        Log "$(cat ${rebuild_log})"
        Log "Print ${KDUMP_CONFIG}"
        grep -v ^\# "${KDUMP_CONFIG}" | grep -v ^$
        Error "Test result: Fail. (Expect ${exp_ret}, got ${act_ret})"
    else
        Log "Test result: Pass. (Expect ${exp_ret}, got ${act_ret})"
    fi
}

MakedumpfileTest()
{
    # Bug 1824327 - [RHEL8.3] kexec-tools: check makedumpfile parameters in advance
    # makedumpfile validation is added in RHEL-8.3.0 kexec-tools-2.0.20-34.el8
    CheckSkipTest kexec-tools 2.0.20-34.el8 && return

    cp -f "${KDUMP_CONFIG}" "${KDUMP_CONFIG}.tmp"
    Log "Restart Kdump Service before testing"
    touch "${KDUMP_CONFIG}"; sleep 2
    LogRun "kdumpctl restart"

    ParamsCheckTest "core_collector makedumpfile -l --message-level 0 -d 31"
    ParamsCheckTest "core_collector makedumpfile -l --message-level 31 -d 31"
    ParamsCheckTest "core_collector makedumpfile -l --message-level 1 -d 31"
    ParamsCheckTest "core_collector makedumpfile -l --message-level 32 -d 31" "FAIL"
    ParamsCheckTest "core_collector makedumpfile -l --message-level -1 -d 31" "FAIL"

    ParamsCheckTest "core_collector makedumpfile -l --message-level 1 -d 0"
    ParamsCheckTest "core_collector makedumpfile -l --message-level 1 -d 31"
    ParamsCheckTest "core_collector makedumpfile -l --message-level 1 -d 1"
    ParamsCheckTest "core_collector makedumpfile -l --message-level 1 -d 32" "FAIL"
    ParamsCheckTest "core_collector makedumpfile -l --message-level 1 -d -1" "FAIL"

    ParamsCheckTest "core_collector makedumpfile -l --message-level 0 -d 31 -F" "FAIL"
    ParamsCheckTest "core_collector cp"
    ParamsCheckTest "core_collector cp -nosuchoption"

    Log "Restore Kdump config"
    cp -f "${KDUMP_CONFIG}" "${KDUMP_CONFIG}.tmp"
    sleep 2;
    touch "${KDUMP_CONFIG}";
    LogRun "kdumpctl restart"
    mv -f "${KDUMP_CONFIG}.tmp" "${KDUMP_CONFIG}"
    Log "Test is done."
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" MakedumpfileTest

