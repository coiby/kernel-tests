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
    if ! [ -d '/mnt/testarea' ]; then
        mkdir /mnt/testarea/
    fi
    OUTPUTFILE=$(mktemp /mnt/testarea/tmp.XXXXXX)
    export OUTPUTFILE
fi

if [ -z "$ARCH" ]; then
    ARCH=$(uname -m)
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

# Most of libcki doesn't require beakerlib
# only load it if the package is installed
# if a test uses beakerlib functions it should install beakerlib as dependency
if [ -e /usr/share/beakerlib/beakerlib.sh ]; then
   # Include beaker library
   source /usr/share/beakerlib/beakerlib.sh
fi

# Result code definitions
CKI_PASS=0        # should go to rlPass()
CKI_FAIL=1        # should go to rlFail()
CKI_UNSUPPORTED=2 # should go to cki_beakerlib_skip_task()
CKI_UNINITIATED=3 # should go to cki_abort_task()

# Status code definitions
CKI_STATUS_COMPLETED=0 # task is completed
CKI_STATUS_ABORTED=1   # task is aborted

# unction to write log
function cki_log()
{
    echo "$*"
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
        rstrnt-report-result "${RSTRNT_TASKNAME}" WARN 99
    else
        rstrnt-report-result "${RSTRNT_TASKNAME}" FAIL 1
    fi
    rstrnt-abort -t recipe
    exit $CKI_STATUS_ABORTED
}

function cki_abort_task()
{
    typeset reason="$*"
    [[ -z $reason ]] && reason="unknown reason"
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    cki_log "Aborting current task: $reason"
    # exit 0 as we want to abort with error and not have restraint to add
    # an exit_code subtest with result FAIL
    exit 0
}

function cki_beakerlib_skip_task()
{
    typeset reason="$*"
    [[ -z $reason ]] && reason="unknown reason"
    rlLog "Skipping current task: $reason"
    rstrnt-report-result "$RSTRNT_TASKNAME" SKIP
    exit $CKI_STATUS_COMPLETED
}

function cki_beakerlib_report_result()
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
            rlFail "$argv"
            ;;
        #
        # NOTE: If a task is aborted or skipped, its cleanup should be done,
        #       or succeeding tasks may be impacted.
        #
        "$CKI_UNSUPPORTED")
            if [[ -n "$cleanup" ]]; then
                rlLog "Now go to cleanup because task is UNSUPPORTED ..."
                eval "$cleanup"
            fi
            typeset reason="UNKNOWN REASON"
            cki_beakerlib_skip_task "$reason"
            ;;
        "$CKI_UNINITIATED")
            if [[ -n "$cleanup" ]]; then
                rlLog "Now go to cleanup because task is UNINITIATED ..."
                eval "$cleanup"
            fi
            typeset reason="UNKNOWN REASON"
            cki_abort_task "$reason"
            ;;
        *)
            cki_abort_task "UNKNOWN REASON #$argv#"
            ;;
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
    rlLog "$hook_startup(): rc=$rc1"
    (( rc += rc1 ))
    cki_beakerlib_report_result $rc1 "$hook_cleanup" "$hook_startup()"
    rlPhaseEnd

    if (( rc == 0 )); then
        typeset tfunc=""
        for tfunc in ${hook_runtest//,/ }; do
            rlPhaseStartTest "$tfunc"
            $tfunc
            typeset -i rc2=$?
            rlLog "$tfunc(): rc=$rc2"
            (( rc += rc2 ))
            cki_beakerlib_report_result $rc2 "$hook_cleanup" "$tfunc()"
            rlPhaseEnd
        done
    fi

    rlPhaseStartCleanup "$hook_cleanup"
    $hook_cleanup
    typeset -i rc3=$?
    rlLog "$hook_cleanup(): rc=$rc3"
    (( rc += rc3 ))
    cki_beakerlib_report_result $rc3 "" "$hook_cleanup()"
    rlPhaseEnd

    rlLog "OVERALL RESULT CODE: $rc"

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
    local timestamp
    timestamp=$(date +"%H:%M:%S")
    echo "[ $timestamp ] Running: '$*'"
    eval "$*"
    return $?
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
    if [[ -x usr/bin/rpm-ostree ]]; then
        echo /usr/bin/rpm-ostree
    elif [[ -x /usr/bin/dnf ]]; then
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

function cki_download_kernel_src_rpm()
{
    if [[ "$(cki_get_yum_tool)" =~ "dnf" ]]; then
        kernelpkg=$(dnf repoquery "/boot/config-$(uname -r)" --queryformat "%{source_name}-%{version}-%{release}" | tail -1)

        cki_run "dnf download --source ${kernelpkg}"
        return $?
    else
        echo "FAIL: cki_download_kernel_src_rpm doesn't support $(cki_get_yum_tool)"
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

    # virt-what returns non empty string. when detected non-baremetal
    if command -v virt-what; then
        hv=$(virt-what)
        [[ -n "$hv" ]] && return 1
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

# return 0 when running kernel 64k
cki_is_kernel_64k()
{
    if [[ $(uname -r) =~ \+64k ]]; then
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
# https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/657
cki_has_kernel_debug_flags()
{
    # ostree check for automotive
    if stat /run/ostree-booted > /dev/null 2>&1; then
        CONFIG=/usr/lib/ostree-boot/config-"$(uname -r)"
    else
        CONFIG=/boot/config-"$(uname -r)"
    fi

    if grep -qwE "CONFIG_LOCKDEP=y|CONFIG_DEBUG_OBJECTS=y" "${CONFIG}"; then
        return 0
    fi
    return 1
}

# return 0 when running kernel automotive. Note will not work with older el9s kernels.
cki_is_kernel_automotive()
{
    if (uname -r | grep -wq "el[0-9].*iv"); then
       return  0
    fi
    return 1
}

cki_is_ostree_booted()
{
    if stat /run/ostree-booted > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

cki_is_qm()
{
   if [ "$(hostnamectl chassis)" == "container" ]; then
       return 0
   fi
   return 1
}

# need to tell which boards are android boot devices.
# as the list of abd boards increase so will this function.

cki_is_abd()
{
    if [ -e /sys/devices/soc0/machine ]; then
        if grep -qi SA8775P /sys/devices/soc0/machine; then
            return 0
        elif grep -qi "Renesas Spider CPU and Breakout boards based on r8a779f0" /sys/devices/soc0/machine; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

