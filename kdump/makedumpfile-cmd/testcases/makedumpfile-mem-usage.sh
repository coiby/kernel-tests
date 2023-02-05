#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

MakedumpfileTest()
{
    [ -f "mem_usage.log" ] && rm -f "mem_usage.log"
    makedumpfile --mem-usage /proc/kcore | tee mem_usage.log
    local ret="${PIPESTATUS[0]}"

    local kernel_nvr
    IFS='.' read -ra kernel_nvr <<<  "${K_VER%%-*}"
    kernel_nvr=$(( kernel_nvr[0] * 100 + kernel_nvr[1] ))

    if [ "${PIPESTATUS[0]}" -ne 0 ] && [ "${kernel_nvr}" -lt 411 ]; then
        Log "Kernel version is < 4.11, option -f is needed"
        makedumpfile -f --mem-usage /proc/kcore | tee mem_usage.log
        ret=${PIPESTATUS[0]}
    fi
    RhtsSubmit "$(pwd)/mem_usage.log"
    if [ "${ret}" -ne 0 ]; then
        Error "'makedumpfile --mem-usage' failed."
        return
    fi

    Log "ERROR MESSAGES BEGIN"
    grep -i -e 'fail' \
         -e 'error' \
         -e 'invalid' \
         -e "can't'" mem_usage.log
    ret=$?
    Log "ERROR MESSAGES END"

    [ "$ret" -eq 0 ] && Error "'makedumpfile --mem-usage' succeeded but output contains error messages. Please check mem_usage.log"
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" MakedumpfileTest
