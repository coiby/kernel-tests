#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

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
    MKPARAM1="-d 31"
    rm -f "1-compression_methods.log"
    for compression in "${params_lst[@]}"; do
        cmdstr="${MKCMD} ${compression} ${MKPARAM1} ${MKPARAM2}"
        Log "CMD: ${cmdstr}"
        ${cmdstr} | tee -a "1-compression_methods.log"
        [ "${PIPESTATUS[0]}" -ne 0 ] && Error "Failed: ${cmdstr}"
    done
    RhtsSubmit "$(pwd)/1-compression_methods.log"

    # 2: dump level with -lzo compression
    rm -f "2-dump_lvl.log"
    params_lst=("-d 7" "-d 9" "-d 16")
    MKPARAM1="-l"
    for dump_lvl in "${params_lst[@]}"; do
        cmdstr="${MKCMD} ${dump_lvl} ${MKPARAM1} ${MKPARAM2}"
        Log "CMD: ${cmdstr}"
        ${cmdstr} | tee -a "2-dump_lvl.log"
        [ "${PIPESTATUS[0]}" -ne 0 ] && Error "Failed: ${cmdstr}"
    done
    RhtsSubmit "$(pwd)/2-dump_lvl.log"

    # 3: message level 1/7 with lzo compression
    rm -f "3-msg_lvl.log"
    params_lst=("--message-level 1" "--message-level 7")
    MKPARAM1="-l -d 31"
    for msg_lvl in "${params_lst[@]}"; do
        cmdstr="${MKCMD} ${msg_lvl} ${MKPARAM1} ${MKPARAM2}"
        Log "CMD: ${cmdstr}"
        ${cmdstr} | tee -a "3-msg_lvl.log"
        [ "${PIPESTATUS[0]}" -ne 0 ] && Error "Failed: ${cmdstr}"
    done
    RhtsSubmit "$(pwd)/3-msg_lvl.log"

    # 4: " -F -l -d 31"
    rm -f "4-F-l-d_31.log"
    MKPARAM1="-F -l -d 31"
    MKPARAM2="/proc/kcore --dry-run --show-stats"
    cmdstr="${MKCMD} ${MKPARAM1} ${MKPARAM2}"
    Log "CMD: ${cmdstr}"
    ${cmdstr} | tee -a "4-F-l-d_31.log"
    [ "${PIPESTATUS[0]}" -ne 0 ] && Error "Failed: ${cmdstr}"
    RhtsSubmit "$(pwd)/4-F-l-d_31.log"

}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" MakedumpfileShowstatsTest
