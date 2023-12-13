#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# handy variables that can be easily parsed
source /etc/os-release

# test-orinted global parameters
PHASE_NAME=${PHASE_NAME:-Test}
PHASE_STATUS=${PHASE_STATUS:-PASS}
PHASE_SCORE=${PHASE_SCORE:-0}
PHASE_START_TIME=0
PHASE_GOOD=0
PHASE_BAD=0
PHASE_TYPE=${PHASE_TYPE:-FAIL}
# OVERALL_STATUS=${OVERALL_STATUS:-PASS}

# kernel, kernel-debug, kernel-rt, kernel-rt-debug, kernel-64k, kernel-64k-debug
kname=$(rpm -q --queryformat '%{name}' -qf "/boot/config-$(uname -r)" | sed 's/-core//')
# 5.14.0, 4.18.0, 3.10.0 - versions are consistent across variants
kver=$(rpm -q --queryformat '%{version}' -qf "/boot/config-$(uname -r)")
# 267.el9, 425.3.1.rt7.213.el8 - releases are variant-specific, kdist is included
krel=$(rpm -q --queryformat '%{release}' -qf "/boot/config-$(uname -r)")

# commonly used global parameters
rhel_x=$(echo $VERSION_ID | cut -d. -f1)
rhel_y=$(echo $VERSION_ID | cut -d. -f2)
nrcpus=$(grep -c ^processor /proc/cpuinfo)

# export variables not directly used in this lib
export kname kver krel nrcpus


# log [-l, --label] message
function log()
{
    # message should be quoted
    local log_label message left
    log_label=LOG
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -l|--label)  log_label=$2; shift 2 ;;
            *)           message="$*"; shift   ;;
        esac
    done

    # print colored labels when executed **manually**
    if [[ "${TERM}" =~ xterm*|screen*|linux|rxvt* ]]; then
        case "${log_label}" in
            PASS)            COLOR="\e[1;32m" ;; # green
            FAIL|FATAL|ERR*) COLOR="\e[1;31m" ;; # red
            WARN*)           COLOR="\e[1;33m" ;; # yellow
            SKIP*|DEBUG*)    COLOR="\e[1;35m" ;; # purple
            BEGIN)           COLOR="\e[1;34m" ;; # blue
            *)               COLOR="" ;;
        esac
        UNCOLOR="\e[00m"
    else
        COLOR=""
        UNCOLOR=""
    fi

    left=$(( ( 10 + ${#log_label} ) / 2 ))
    printf ":: [ %s ] :: [%b%*s%*s%b] :: %s\n" \
           "$(date '+%T')" \
           "${COLOR}" "${left}" "${log_label}" "$((10-left))" '' "${UNCOLOR}" \
           "${message}" \
        | tee -a "${OUTPUTFILE}"
    return "${PIPESTATUS[0]}"
}
function log_raw()   { printf "%b" "$*" | tee -a "${OUTPUTFILE}" ; }
function log_pass()  { log --label PASS "$*" ; }
function log_warn()  { log --label WARN "$*" ; }
function log_fail()  { log --label FAIL "$*" ; }
function log_begin() { log --label BEGIN "$*" ; }
function log_end()   { log --label END "$*" ; }


# phase_start [name] [type]
function phase_start()
{
    # phase_end and phase_start should be used in the same **bash process**
    PHASE_START_TIME=$SECONDS
    PHASE_STATUS=PASS # refresh the value of the new phase
    PHASE_NAME=${1:-PHASE_NAME}
    PHASE_TYPE=${2:-PHASE_TYPE}
    PHASE_GOOD=0
    PHASE_BAD=0

    if [[ "${PHASE_TYPE}" != FAIL ]] && [[ "${PHASE_TYPE}" != WARN ]] ; then
        log_warn "Unknown phase type: ${PHASE_TYPE}"
        log_warn "Using default phase type: FAIL"
        PHASE_TYPE=FAIL
    fi

    log_raw "\n::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::\n"
    log_raw "::   ${PHASE_NAME}\n"
    log_raw "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::\n\n"
    PHASE_STATUS=PASS
}

function phase_start_test()
{
    local phase_name
    phase_name=${1:-TEST}
    phase_start "${phase_name}" FAIL
}

function phase_start_setup() { phase_start Setup WARN ; }
function phase_start_cleanup() { phase_start Cleanup WARN ; }


function phase_end()
{
    : $(( PHASE_DURATION = SECONDS - PHASE_START_TIME ))

    # This is the only place PHASE_TYPE is used
    if [[ "${PHASE_TYPE}" == WARN ]] && [[ "${PHASE_STATUS}" == FAIL ]]; then
        PHASE_STATUS=WARN
    fi

    log_raw "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::\n"
    log_raw "::   Duration: $((PHASE_DURATION / 60))m $((PHASE_DURATION % 60))s\n"
    log_raw "::   Assertions: ${PHASE_GOOD} good, ${PHASE_BAD} bad\n"
    log_raw "::   RESULT: ${PHASE_STATUS} (${PHASE_NAME})\n\n"
    report_result "${PHASE_NAME}" "${PHASE_STATUS}" "${PHASE_SCORE}"
}


# run -l command [expected,[expected...] [comment]]
function run()
{
    local args logonly commands expected comment exit_code
    args=()
    logonly=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -l|--lol|--logonly)  logonly=true; shift ;;
            *)            args+=("$1"); shift ;;
        esac
    done
    set -- "${args[@]}"

    commands=$1
    expected=${2:-0}
    comment=${3:-""}

    [[ -n $comment ]] && log "${comment}"
    log_begin "Running '${commands}'"
    # TODO remove color chars before redirecting outputs to an actual file
    eval "${commands}" > >(tee -a "${OUTPUTFILE}") 2>&1
    exit_code=$?

    if [[ "${logonly}" == true ]]; then
        log_end "Command '${commands}' (Expected ${expected}, got ${exit_code})"
        return $exit_code
    fi

    if ! echo "${expected}" | grep -q "\<${exit_code}\>"; then
        # This parameter is used only when "phase" is used, it doesn't
        # (shouldn't) affect the test otherwise
        PHASE_STATUS=FAIL
        : $(( PHASE_BAD++ ))
        log_fail "Command '${commands}' (Expected ${expected}, got ${exit_code})"
    else
        : $(( PHASE_GOOD++ ))
        log_pass "Command '${commands}' (Expected ${expected}, got ${exit_code})"
    fi

    return $exit_code
}


# oneliner command run_name
function oneliner()
{
    local commands run_name
    commands=$1
    run_name=${2:-${commands}}
    phase_start_test "${run_name}"
    run "${commands}"
    phase_end
}


# report_result name [status] [score]
function report_result()
{
    local test_name=$1
    local test_status=$2
    local test_score=${3:-0}

    if [[ -n "$RSTRNT_JOBID" ]]; then
        rstrnt-report-result "${test_name}" "${test_status}" "${test_score}"
    fi

    # flush the logfile so that each phase in Beaker UI has only their own logs
    cat "${OUTPUTFILE}" >> "${OUTPUTFILE}.sofar"
    : > "${OUTPUTFILE}"
}


# dummy wrapper that should be added to the end of a runtest.sh
function test_finish()
{
    # restore the complete test logs
    cat "${OUTPUTFILE}.sofar" > "${OUTPUTFILE}"
}


if [[ -z "$OUTPUTFILE" ]]; then
    export OUTPUTFILE=$(mktemp)
    log "OUTPUTFILE not set, using ${OUTPUTFILE} for logging"
fi

# == shared convenience functions ==

function convert_number_range() {
    # converts a range of cpus, like "1-3,5" to a list, like "1,2,3,5"
    local cpu_range=$1
    local cpus_list=""
    local cpus=""
    for cpus in ${cpu_range//,/ }; do
        if echo "$cpus" | grep -q -- "-"; then
            cpus="${cpus//-/ }"
            cpus=$(seq $cpus | sed -e 's/ /,/g')
        fi
        for cpu in $cpus; do
            cpus_list="$cpus_list,$cpu"
        done
   done
   # shellcheck disable=SC2001
   cpus_list=$(echo $cpus_list | sed -e 's/^,//')
   echo "$cpus_list"
}

function get_isolated_cores()
{
    declare cpuset
    # Try to get isolated cores from /cpu/isolated, which should be sufficient
    # for most baremetal testing.  If empty, try /cpu/nohz_full, which
    # should be sufficient for OCP/SNO systems.
    cpuset=$(cat /sys/devices/system/cpu/isolated)
    [ -z $cpuset ] && cpuset=$(cat /sys/devices/system/cpu/nohz_full)
    [[ "$cpuset" == *"null"* ]] && cpuset=""
    echo ${cpuset}
}

function get_housekeeping_cores()
{
    declare cpuset
    # Get the list of non-isolated CPUs
    cpuset=$(grep "Cpus_allowed_list:" /proc/self/status | cut -f 2)
    echo ${cpuset}
}

# ver1 <= rhel <= ver2
function rhel_in_range() { printf '%s\n' "$1" "${rhel_x}.${rhel_y}" "$2" | sort -VC; }
