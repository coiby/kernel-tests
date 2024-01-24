#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

VerifyScrub() {
    local vmcore_file="$1"
    local verify_log="split_veri_scrub_$(basename $vmcore_file).log"
    local err_msg="VerifyScrub: FAIL. Check ${verify_log} for details."

    Log "Start VerifyScrub"
    echo > "${verify_log}"
    # shellcheck disable=SC2154
    crash "${vmlinux}" "${vmcore_file}" <<< "q" > "${verify_log}"
    [ $? -ne 0 ] && {
        RhtsSubmit "$(pwd)/${verify_log}"
        Error "$err_msg"
        return 1
    }

    local task_addr=$(awk '/TASK:/ {print $2}' "${verify_log}")

    cat <<EOF > crash_split.cmd
p jiffies
list task_struct.tasks -s task_struct.utime -h ${task_addr}
q
EOF
    RhtsSubmit "$(pwd)/crash_split.cmd"
    LogRun "crash --hex -i crash_split.cmd ${vmlinux} ${vmcore_file} > \"${verify_log}\""
    local retval=$?
    RhtsSubmit "$(pwd)/${verify_log}"

    if [ "${retval}" -ne 0 ]; then
        Error "$err_msg"
    else
        while read -r line; do
            if [[ "${line}" =~ (jiffies|utime)\ =\ .*0x([[:xdigit:]]+) && \
            ! "${BASH_REMATCH[2]}" =~ ^(58)+$ ]]; then
                Error "$err_msg"
            fi
        done <"${verify_log}"
    fi

    rm -f "${verify_log}" crash_split.cmd
    Log "VerifyScrub: PASS"
}


SplitTest(){
    local options="$1"
    local split="dumpfile_{1,2,3}"

    Log "Test makedumpfile split & reassemble with ${options}"
    # Split the vmcore
    rm -f /tmp/dumpfile_*
    # shellcheck disable=SC2154
    LogRun "makedumpfile --split -d 31 -x ${vmlinux} ${options} ${vmcore} /tmp/${split}" || {
        Error "The makedumpfile split command failed"
        return
    }

    # Assemble vmcore files
    local assembled="vmcore.$(date +%s)"
    LogRun "makedumpfile --reassemble /tmp/${split} /tmp/${assembled}"
    if [ $? -eq 0 ]; then
        # Verify the assembled vmcore file
        [[ "$options" =~ (scrub\.c|scrub\.conf) ]] && VerifyScrub "/tmp/${assembled}"
    else
        Error "The makedumpfile reassemble command failed"
    fi

    rm -f "/tmp/${assembled}" /tmp/dumpfile_*
}

MakedumpfileTest(){
    PrepareCrash
    CheckVmlinux
    GetCorePath

    SplitTest "--config \"testcases/scrub.conf\""
#    SplitTest "--eppic \"testcases/scrub.c\""
}

MultihostStage "$(basename "${0%.*}")" MakedumpfileTest