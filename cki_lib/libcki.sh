#!/bin/bash
#
# Common helper functions and global variables to be used by all CKI tests
#
# NOTE: To make coding style consistent, conventions in the following should be
#       followed:
#       1) All helper functions start with 'cki_';
#       2) All global variables start with 'CKI_'.
#

# Set CKI test environment
if [ -z "$OUTPUTFILE" ]; then
    OUTPUTFILE=$(mktemp /mnt/testarea/tmp.XXXXXX)
    export OUTPUTFILE
fi

if [ -z "$ARCH" ]; then
    ARCH=$(uname -i)
fi

if [ -z "$FAMILY" ]; then
    FAMILY=$(sed -e 's/\(.*\)release\s\([0-9]*\).*/\1\2/; s/\s//g' /etc/redhat-release)
fi

# Set RHTS REBOOTCOUNT to Restraint compatiable environent variable
export REBOOTCOUNT=${RSTRNT_REBOOTCOUNT:-0}

# Set well-known logname so users can easily find
# current tasks log file.  This well-known file is also
# used by the local watchdog to upload the log
# of the current task.
if [ -h /mnt/testarea/current.log ]; then
    ln -sf "$OUTPUTFILE" /mnt/testarea/current.log
else
    ln -s "$OUTPUTFILE" /mnt/testarea/current.log
fi

# Include beaker library
source /usr/share/beakerlib/beakerlib.sh

CKI_RC_POS=0
CKI_RC_NEG="1-255"
CKI_RC_ANY="0-255" # To assist rlRun() to support any return code

# Result code definitions
CKI_PASS=0        # should go to rlPass()
CKI_FAIL=1        # should go to rlFail()
CKI_UNSUPPORTED=2 # should go to cki_skip_task()
CKI_UNINITIATED=3 # should go to cki_abort_task()

# Status code definitions
CKI_STATUS_COMPLETED=0 # task is completed
CKI_STATUS_ABORTED=1   # task is aborted

# unction to write log
function cki_log()
{
    echo "$*"
}

# Wrapper function to write log
function cki_beakerlib_log()
{
    rlLog "$*"
}

#
# When a serious problem occurs and we cannot proceed any further, we abort
# this recipe with an error message.
#
# Arguments:
#   $1 - the message to print in the log
#   $2 - 'WARN' or 'FAIL'
#
function cki_abort_recipe()
{
    typeset failure_message="$1"
    typeset failure_type=${2:-"FAIL"}

    echo "❌ ${failure_message}"
    if [[ "$failure_type" == 'WARN' ]]; then
        rstrnt-report-result "${TEST}" WARN 99
    else
        rstrnt-report-result "${TEST}" FAIL 1
    fi
    rstrnt-abort -t recipe
    exit $CKI_STATUS_ABORTED
}

function cki_abort_task()
{
    typeset reason="$*"
    [[ -z $reason ]] && reason="unknown reason"
    rstrnt-report-result "${TEST}" WARN
    cki_log "Aborting current task: $reason"
    rstrnt-abort --server "$RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status"
    exit $CKI_STATUS_ABORTED
}

function cki_skip_task()
{
    typeset reason="$*"
    [[ -z $reason ]] && reason="unknown reason"
    cki_beakerlib_log "Skipping current task: $reason"
    rstrnt-report-result "$TEST" SKIP
    exit $CKI_STATUS_COMPLETED
}

function cki_report_result()
{
    typeset rc=${1?"*** result code"}
    typeset cleanup=$2
    shift 2
    typeset argv="$*"
    case $rc in
        "$CKI_PASS")
            rlPass "$argv"
            ;;
        "$CKI_FAIL")
            rlFail "$argv $g_reason_fail"
            ;;
        #
        # NOTE: If a task is aborted or skipped, its cleanup should be done,
        #       or succeeding tasks may be impacted.
        #
        "$CKI_UNSUPPORTED")
            if [[ -n "$cleanup" ]]; then
                cki_beakerlib_log "Now go to cleanup because task is UNSUPPORTED ..."
                eval "$cleanup"
            fi
            typeset reason=$g_reason_unsupported
            [[ -z "$reason" ]] && reason="UNKNOWN REASON"
            cki_skip_task "$reason"
            ;;
        "$CKI_UNINITIATED")
            if [[ -n "$cleanup" ]]; then
                cki_beakerlib_log "Now go to cleanup because task is UNINITIATED ..."
                eval "$cleanup"
            fi
            typeset reason=$g_reason_uninitiated
            [[ -z $reason ]] && reason="UNKNOWN REASON"
            cki_abort_task "$reason"
            ;;
        *)
            cki_abort_task "$g_reason_other #$argv#"
            ;;
    esac
}

#
# Set reason for according to result code, once function cki_report_result() is
# invoked, the related reason will be used when calling cki_beakerlib_log()
#
function cki_set_reason()
{
    typeset rc=${1?"*** result code"}
    shift
    cki_beakerlib_log "$*"
    case $rc in
        "$CKI_FAIL") g_reason_fail="$*" ;;
        "$CKI_UNSUPPORTED") g_reason_unsupported="$*" ;;
        "$CKI_UNINITIATED") g_reason_uninitiated="$*" ;;
        *) g_reason_other="$rc is an invalid result code" ;;
    esac
}

function runtest() { :; }
function startup() { :; }
function cleanup() { :; }
function cki_main()
{
    typeset hook_runtest=${1:-"runtest"}
    typeset hook_startup=${2:-"startup"}
    typeset hook_cleanup=${3:-"cleanup"}
    typeset -i rc=0

    rlJournalStart

    rlPhaseStartSetup "$hook_startup"
    $hook_startup
    typeset -i rc1=$?
    cki_beakerlib_log "$hook_startup(): rc=$rc1"
    (( rc += rc1 ))
    cki_report_result $rc1 "$hook_cleanup" "$hook_startup()"
    rlPhaseEnd

    if (( rc == 0 )); then
        typeset tfunc=""
        for tfunc in ${hook_runtest//,/ }; do
            rlPhaseStartTest "$tfunc"
            $tfunc
            typeset -i rc2=$?
            cki_beakerlib_log "$tfunc(): rc=$rc2"
            (( rc += rc2 ))
            cki_report_result $rc2 "$hook_cleanup" "$tfunc()"
            rlPhaseEnd
        done
    fi

    rlPhaseStartCleanup "$hook_cleanup"
    $hook_cleanup
    typeset -i rc3=$?
    cki_beakerlib_log "$hook_cleanup(): rc=$rc3"
    (( rc += rc3 ))
    cki_report_result $rc3 "" "$hook_cleanup()"
    rlPhaseEnd

    cki_beakerlib_log "OVERALL RESULT CODE: $rc"

    rlJournalEnd

    #
    # XXX: Don't return the overall result code (i.e. $rc) but always return 0
    #      (i.e. CKI_STATUS_COMPLETED) to make sure beaker task is not marked
    #      as 'Aborted' if test result is marked as 'Fail'
    #
    return $CKI_STATUS_COMPLETED
}

#
# Basic function that prints the command to run before running it
# Similar to rlRun, but doesn't require beakerlib
#
function cki_run()
{
    typeset timestamp=$(date +"%H:%M:%S")
    echo "[ $timestamp ] Running: '$*'"
    eval "$@"
    return $?
}

#
# Wrapper functions to run a single cmd
# o cki_run_cmd_pos(): $? must be 0
# o cki_run_cmd_neg(): $? must be !0
# o cki_run_cmd_neu(): don't care about $?
#
function cki_run_cmd_pos()
{
    typeset cmd="$*"
    (( ${#cmd} > 64 )) && cmd="${cmd:0:63}..."
    typeset msg="[ POS ] run '$cmd', expect to pass"
    rlRun -l "$@" "$CKI_RC_POS" "$msg"
    return $?
}

function cki_run_cmd_neg()
{
    typeset cmd="$*"
    (( ${#cmd} > 64 )) && cmd="${cmd:0:63}..."
    typeset msg="[ NEG ] run '$cmd', expect to fail"
    if rlRun -l "$@" "$CKI_RC_NEG" "$msg" ; then
        return 1
    else
        return 0
    fi
}

function cki_run_cmd_neu()
{
    typeset cmd="$*"
    (( ${#cmd} > 64 )) && cmd="${cmd:0:63}..."
    typeset msg="[ NEU ] run '$cmd', expect nothing"
    rlRun -l "$@" "$CKI_RC_ANY" "$msg"
    return $?
}

# Wrapper function to change working directory
function cki_cd()
{
    rlRun "pushd $(pwd)"
    rlRun "cd $1"
}

# Wrapper function to return to original working directory
function cki_pd()
{
    rlRun "popd"
}

#
# Enable to debug bash script by resetting PS4. If user wants to turn debug
# switch on, just set env DEBUG, e.g.
# $ export DEBUG=yes
#
function cki_debug()
{
    typeset -l s=$DEBUG
    if [[ "$s" == "yes" || "$s" == "true" ]]; then
        export PS4='__DEBUG__: [$FUNCNAME@$BASH_SOURCE:$LINENO|$SECONDS]+ '
        set -x
    fi
}

function cki_get_yum_tool()
{
    if [[ -x /usr/bin/dnf ]]; then
        echo /usr/bin/dnf
    elif [[ -x /usr/bin/yum ]]; then
        echo /usr/bin/yum
    else
        echo "No tool to download kernel from a repo" >&2
        rstrnt-abort -t recipe
        exit 0
    fi
}

function cki_upload_log_file()
{
    typeset logfile=${1?"*** log file ***"}
    echo "Upload log file $logfile ..."
    rstrnt-report-log -l "$logfile"
}

# Print an informational message with a friendly emoji.
function cki_print_info()
{
    echo "ℹ️ ${1}"
}

# Print a success message with a friendly emoji.
function cki_print_success()
{
    echo "✅ ${1}"
}

# Print an warning message with a friendly emoji.
function cki_print_warning()
{
    echo "⚠️ ${1}"
}

# Check if the passed variable has a truthy value or not.
# Args: Variable
# Returns: 0 if the variable is truthy, 1 otherwise
# (copied from gitlab.com/cki-project/cki-lib/cki_utils.sh)
function cki_is_true()
{
    if [[ "${1}" = [Tt]rue ]] ; then
        return 0
    else
        return 1
    fi
}

# Check the system under test is bare metal or not
# XXX: It is mainly for the beaker lab, hence s390x system is not regared as
#      bare metal on purpose
function cki_is_baremetal()
{
    # system with shared resources
    # any s390x system
    uname -m | grep -q s390 && return 1

    # any guest system, e.g. ppc64 guests
    hostname | grep -q guest && return 1

    hostname | grep -q "\-vm\-" && return 1

    # any ppc lpar
    (uname -m | grep -q ppc) && (hostname | grep -q "\-lp") && return 1

    if command -v virt-what; then
        hv=$(virt-what)
        [[ -z "$hv" ]] && return 1
    fi

    return 0
}

# Check the system under test is vm or not
function cki_is_vm()
{
    cki_is_baremetal && return 1 || return 0
}

# Functions to compare kernel versions
function cki_kernel_version()
{
    _ver=$(uname -r | sed "s/+debug//" | sed "s/\.gcov//" | sed "s/\.$(arch)//")
    # shellcheck disable=SC2001
    echo "${_ver}" | sed "s/\.el[0-9].*\|\.fc.*\|\.eln.*//"
}

function _cki_version_le()
{
    { echo "$1"; echo "$2"; } | sort -V | tail -n 1 | grep -qx "$2"
}

function cki_kver_ge() { _cki_version_le "$1" "$(cki_kernel_version)"; }
function cki_kver_le() { _cki_version_le "$(cki_kernel_version)" "$1"; }
function cki_kver_lt() { ! cki_kver_ge "$1"; }
function cki_kver_gt() { ! cki_kver_le "$1"; }

# return 0 when running kernel rt
cki_is_kernel_rt()
{
    if [[ $(uname -r) =~ "rt" ]]; then
       return  0
    fi
    return 1
}

# return 0 when running kernel debug
cki_is_kernel_debug()
{
    if [[ $(uname -r) =~ "debug" ]]; then
       return  0
    fi
    return 1
}

# return 0 when running kernel with debug flags
# Some kernels are built with debug flags, but they don't have debug suffix
# For example some ELN kernel builds in koji
# Check for debug options that can cause performance issues
# handle these sort of kernel as debug kernels
# https://gitlab.com/cki-project/kernel-tests/-/issues/657
cki_has_kernel_debug_flags()
{
    if grep -qwE "CONFIG_LOCKDEP=y|CONFIG_DEBUG_OBJECTS=y" /boot/config-"$(uname -r)"; then
        return 0
    fi
    return 1
}

# return 0 when running kernel auto
cki_is_kernel_auto()
{
    if rpm -q "kernel-auto-$(uname -r)" > /dev/null 2>&1; then
       return  0
    fi
    return 1
}
