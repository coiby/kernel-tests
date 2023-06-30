#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

if [ "${RELEASE}" -lt 8 ]; then
    Skip "This feature is not supported."
    Report
fi

if $IS_RHEL9;then
    CheckSkipTest kexec-tools 2.0.23-5 && Report
elif $IS_RHEL8;then
    CheckSkipTest kexec-tools 2.0.20-66 && Report
fi

MakedumpfileShowstatsTest()
{
    # 1-compression methods:
    # makedumpfile -z/c/l/p/E -d 31 /proc/kcore vmcore --dry-run --show-stats

    # 2-dump level with lzo compression
    # makedumpfile -l     -d 7/9/16 /proc/kcore vmcore --dry-run --show-stats

    # 3-message level 1/7 with lzo compression
    # makedumpfile -l --message-level 1/7 -d 31 /proc/kcore vmcore --dry-run --show-stats
    # makedumpfile --message-level 1 -d 31 /proc/kcore vmcore --dry-run --show-stats

    # 4-" -F -l -d 31"
    # makedumpfile -F -l -d 31 /proc/kcore --dry-run --show-stats

    local MKCMD="makedumpfile"
    local MKPARAM1=""
    local MKPARAM2="/proc/kcore vmcore --dry-run --show-stats"
    local cmdstr=""

    # 1: compression_methods
    local params_lst=("-z" "-c" "-l" "-p" "-E")
    local logfile="1-compression_methods.log"
    rm -f "${logfile}"
    MKPARAM1="-d 31"
    for compression in "${params_lst[@]}"; do
        cmdstr="${MKCMD} ${compression} ${MKPARAM1} ${MKPARAM2}"
        Log "CMD: ${cmdstr}"
        ${cmdstr} | tee -a "${logfile}"
        [ "${PIPESTATUS[0]}" -ne 0 ] && Error "Failed: ${cmdstr}, please check log:${logfile}"
    done
    RhtsSubmit "$(pwd)/${logfile}"

    # 2: dump level with -lzo compression
    logfile="2-dump_lvl.log"
    rm -f "${logfile}"
    params_lst=("-d 7" "-d 9" "-d 16")
    MKPARAM1="-l"
    for dump_lvl in "${params_lst[@]}"; do
        cmdstr="${MKCMD} ${dump_lvl} ${MKPARAM1} ${MKPARAM2}"
        Log "CMD: ${cmdstr}"
        ${cmdstr} | tee -a "${logfile}"
        [ "${PIPESTATUS[0]}" -ne 0 ] && Error "Failed: ${cmdstr}, please check log:${logfile}"
    done
    RhtsSubmit "$(pwd)/${logfile}"

    # 3: message level 1/7 with lzo compression
    logfile="3-msg_lvl.log"
    rm -f "${logfile}"
    params_lst=("--message-level 1" "--message-level 7")
    MKPARAM1="-l -d 31"
    for msg_lvl in "${params_lst[@]}"; do
        cmdstr="${MKCMD} ${msg_lvl} ${MKPARAM1} ${MKPARAM2}"
        Log "CMD: ${cmdstr}"
        ${cmdstr} | tee -a "${logfile}"
        [ "${PIPESTATUS[0]}" -ne 0 ] && Error "Failed: ${cmdstr}, please check log:${logfile}"
    done
    RhtsSubmit "$(pwd)/${logfile}"

    # 4: " -F -l -d 31"
    logfile="4-F-l-d_31.log"
    rm -f "${logfile}"
    MKPARAM1="-F -l -d 31"
    MKPARAM2="/proc/kcore --dry-run --show-stats"
    cmdstr="${MKCMD} ${MKPARAM1} ${MKPARAM2} 2>&1"
    Log "CMD: ${cmdstr}"
    ${cmdstr} | tee -a "${logfile}"
    [ "${PIPESTATUS[0]}" -ne 0 ] && Error "Failed: ${cmdstr}, please check log:${logfile}"
    RhtsSubmit "$(pwd)/${logfile}"

}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" MakedumpfileShowstatsTest
