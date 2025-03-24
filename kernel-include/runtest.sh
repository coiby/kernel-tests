#!/bin/bash

# Kernel Testing Include File:
#  This include file contains common variables and
#  functions for "KT1" and "Secondary" kernel testing tasks.

#
# Variables
#
# control where to log debug messages to:
# devnull = 1 : log to /dev/null
# devnull = 0 : log to file specified in ${DEBUGLOG}
devnull=0

# don't run it if running as part of shellspec
# https://github.com/shellspec/shellspec#__sourced__
if [ ! "${__SOURCED__:+x}" ]; then
    # Create debug log
    DEBUGLOG=$(mktemp -p /mnt/testarea -t DeBug.XXXXXX)
    K_DEBUGLOG=$(mktemp -p /mnt/testarea -t K_DeBug.XXXXXX)

    # In the event your not running automated Beaker job
    if [ -z "$OUTPUTFILE" ]; then
        echo ""
        echo "***** \$OUTPUTFILE is not defined "
        echo "***** This is generally do to a "
        echo "***** manual testing setup  "
        echo "***** Creating: \$OUTPUTFILE "
        echo ""
        export OUTPUTFILE=$(mktemp /mnt/testarea/tmp.XXXXXX)
    fi
    # ToDo: $RESULT_SERVER $TESTID also need workaround

    OUTPUTDIR=/mnt/testarea
    if [ ! -d "$OUTPUTDIR" ]; then

        echo ""
        echo "***** OUTPUTDIR is not defined "
        echo "***** Creating: $OUTPUTDIR  "
        echo ""
        mkdir -p $OUTPUTDIR
    fi

    # locking to avoid races
    lck=$OUTPUTDIR/$(basename $0).lck
    K_LCK=$OUTPUTDIR/$(basename $0).lck

    # shellcheck disable=SC2034
    TESTAREA="/mnt/testarea"
    # shellcheck disable=SC2034
    K_TESTAREA="/mnt/testarea"
    # shellcheck disable=SC2034
    TEST_VER=$(rpm -qf $0)
    # shellcheck disable=SC2034
    K_TEST_VER=$(rpm -qf $0)

    # Kernel Variables
    K_NAME=$(rpm -q --queryformat '%{name}\n' -qf /boot/config-$(uname -r))
    #   example output: kernel
    K_VER=$(rpm -q --queryformat '%{version}\n' -qf /boot/config-$(uname -r))
    #   example output: 2.6.32
    K_VARIANT=$(echo $K_NAME | sed -e "s/kernel//g")
    #   are we a DEBUG kernel?
    # shellcheck disable=SC2034
    K_REL=$(rpm -q --queryformat '%{release}\n' -qf /boot/config-$(uname -r))
    #   example output: 220.el6
    K_SRC=$(rpm -q --queryformat '%{sourcerpm}\n' -qf /boot/config-$(uname -r))
    #   example output: kernel-2.6.32-220.el6.src.rpm
    # shellcheck disable=SC2034
    K_BASE=$(rpm -q --queryformat '%{name}-%{version}-%{release}.%{arch}\n' -qf /boot/config-$(uname -r))
    #   example output: kernel-2.6.32-220.el6.x86_64
    K_ARCH=$(rpm -q --queryformat '%{arch}' -f /boot/config-$(uname -r))
    #   example output: x86_64
    #   example output: armv7hl
    #   example output: armv7l
    # shellcheck disable=SC2034
    K_RUNNING=$(uname -r)
    #   example output: 2.6.32-220.el6.x86_64
    #   We removed the dot between release and variant because kernels built
    #   under rhel5 did not include this dot and will make comparing difficult.
    #   Release and variant on fedora kernels can use also + sign,
    #   example input: 3.15.0-0.rc5.git0.1.el7.x86_64+debug
    # shellcheck disable=SC2034
    K_RUNNING_VR=$(uname -r | sed -e "s/\.${K_ARCH}[.+]*//")
    #   example output: 3.6.10-8.fc18highbank
    # shellcheck disable=SC2034
    K_DOWNLOAD="http://download.lab.bos.redhat.com/brewroot/packages/kernel/"
    #
    # shellcheck disable=SC2034
    RH_REL=$(cat /etc/redhat-release | cut -d" " -f7)
    #   example output: 6.2
    # shellcheck disable=SC2034
    K_CONFIG="kernel-$K_VER-$K_ARCH$K_VARIANT.config"
    #   example output: kernel-2.6.32-x86_64.config

    # This is a little cryptic, in practice it takes the full src rpm file
    # name and strips everytihng after (including) the version, leaving just
    # the src rpm package name.
    # Needed when the kernel rpm comes from of e.g. kernel-pegas src rpm.
    # shellcheck disable=SC2034
    K_SPEC_NAME=${K_SRC%%-${K_VER}*}
fi # end of if [ ! "${__SOURCED__:+x}" ]

#
# Functions
#
# Log a message to the ${DEBUGLOG} or to /dev/null
function DeBug ()
{
    local msg=$1
    local timestamp
    timestamp=$(date '+%F %T')
    if [ "$devnull" = "0" ]; then
        (
            flock -x 200 2>/dev/null
            echo -n "${timestamp}: " >> $DEBUGLOG 2>&1
            echo "${msg}" >> $DEBUGLOG 2>&1
        )   200>$lck
    else
        echo "${msg}" > /dev/null 2>&1
    fi
}

# shellcheck disable=SC2120
function RprtRslt ()
{
    echo "" | tee -a $OUTPUTFILE
    echo "***** End of runtest.sh " | tee -a $OUTPUTFILE
    local score

    local task=$1

    # Default result to FAIL
    local result="FAIL"

    # score of 0 is PASS. score of 99 is PASS, as test is skipped
    # If no score is given, default to fail and count the reported fails
    # Then post-process the results to find the regressions
    if [ -z "$2" ]; then
      score=$(grep -c "FAILED: " $OUTPUTFILE)
    else
      score=$2
    fi

    if [ ! -s "$OUTPUTFILE" ]; then
        local result="FAIL"
    else
        if [ "$score" -eq "0" ] || [ "$score" -eq "99" ]; then
            local result="PASS"
        else
            local result="FAIL"
        fi
    fi

    # File the results in the database
    report_result $task $result $score
    SubmitLog $DEBUGLOG
    exit 0
}

function SubmitLog ()
{
    local log=$1
    rhts_submit_log -S $RESULT_SERVER -T $TESTID -l $log
}

function EstatusReport ()
{

    if [ "$?" -ne "0" ]; then
        local report=$1
        local concern=$2

        ReportStatus "$report" "$concern"
    fi
}

function EstatusFail ()
{

    if [ "$?" -ne "0" ]; then
        local problem=$1

        DisplayFailandBail "$problem"
    fi
}

function DisplayFailandBail ()
{
    # Display the fail in a informative format and feed RprtRslt

    local issue=$1

    DeBug "Failed: $issue"
    echo  "***** FAILED: $issue " | tee -a $OUTPUTFILE

    RprtRslt
}

function report_result ()
{
    rhts-report-result "$1" "$2" "$OUTPUTFILE" "$3"
}

function ReportStatus ()
{
    # Report test status
    # $3 is optional and enhances functionality

    local status=$1
    local message=$2

    DeBug "$status: $message"
    echo  "***** $status: $message " | tee -a $OUTPUTFILE

    # If $3 is provided, report_result and continue testing
    if [ -n "$3" ]; then
        local string=/$3

        # Default to FAIL
        if [ "$status" = "Passed" ]; then
            local result="PASS"
        else
            local result="FAIL"
        fi

        # Then file the results in the database
        report_result ${TEST}${string} $result
    fi
}

######################################################
# Below is a copy of the functions using new
# naming scheme: K_FunctionName
# If accepted tasks using kernel/include will
# be updated and old function names removed.


# REBOOTCOUNT is a Beaker env variable set equal to 0
# Any test that reboots by design needs a workaround
# Suggestion: define ExpectedRebootCount in test
# then we can update this function to check variables
function K_CheckRebootCount ()
{
    if [ -n "$REBOOTCOUNT" ]; then
        if [ "$REBOOTCOUNT" -gt "0" ]; then
            echo "" | tee -a $OUTPUTFILE
            echo "***** System rebooted " | tee -a $OUTPUTFILE
            echo "***** Check logs for oops or panic " | tee -a $OUTPUTFILE
            echo "***** End of runtest.sh " | tee -a $OUTPUTFILE
            report_result "system_rebooted" "WARN"
            K_SubmitLog "$K_DEBUGLOG"
            exit 0
        fi
    fi
}

# This is a temporary function.
# ToDo: PBunyan needs modify a few tests to use new function name scheme
function checkRebootCount ()
{
    K_CheckRebootCount
}

function K_DeBug ()
{
    local msg="$1"
    local timestamp
    timestamp="$(date '+%F %T')"

    if [ "$devnull" = "0" ]; then
        (
            flock -x 200 2>/dev/null
            echo -n "${timestamp}: " >> $K_DEBUGLOG 2>&1
            echo "${msg}" >> $K_DEBUGLOG 2>&1
        )   200>$K_LCK
    else
        echo "${msg}" > /dev/null 2>&1
    fi
}

function K_SubmitLog ()
{
    local log="$1"

    rhts_submit_log -S "$RESULT_SERVER" -T "$TESTID" -l "$log"
}

function K_ReportResult ()
{
    local score
    local task="$1"

    # Default result to FAIL
    local result="FAIL"

    echo "" | tee -a $OUTPUTFILE
    echo "***** End of runtest.sh " | tee -a $OUTPUTFILE

    # score of 0 is PASS. score of 99 is PASS, as test is skipped
    # If no score is given, default to fail and count the reported fails
    # Then post-process the results to find the regressions
    if [ -z "$2" ]; then
        score=$(grep -c "FAILED: " $OUTPUTFILE)
    else
        score="$2"
    fi

    if [ ! -s "$OUTPUTFILE" ]; then
        local result="FAIL"
    else
        if [ "$score" -eq "0" ] || [ "$score" -eq "99" ]; then
            local result="PASS"
        else
            local result="FAIL"
        fi
    fi

    # File the results in the database
    report_result "$task" "$result" "$score"
    K_SubmitLog "$K_DEBUGLOG"
    exit 0
}

function K_ReportStatus ()
{
    # Report test status
    # $3 is optional, as its inclusion triggers report_result

    local status="$1"
    local message="$2"

    K_DeBug " $status: $message"
    echo "***** $status: $message " | tee -a $OUTPUTFILE

    # If $3 is provided, report_result and continue testing
    if [ -n "$3" ]; then
        local task=/"$3"

        # Default result to FAIL
        case $status in
        Passed)
            local result="PASS"
        ;;
        Warn)
            local result="WARN"
        ;;
        *)
            local result="FAIL"
        ;;
        esac

        # Then file the results in the database
        report_result "${TEST}${task}" "$result"
    fi
}

function K_EchoAll ()
{
    # echo an entry for debugging
    # echo output

    local text="$1"

    K_DeBug " $text"
    echo "***** $text " | tee -a $OUTPUTFILE
}

function K_ReportFailandBail ()
{
    # Display the fail in a informative format and feed K_ReportResult

    local issue="$1"
    local task="$2"

    K_DeBug " FAILED: $issue"
    echo "***** FAILED: $issue " | tee -a $OUTPUTFILE

    K_ReportResult "$task"
}

function K_EstatusFail ()
{
    # Check the exit status
    # If command fails, report the issue and exit the test

    if [ "$?" -ne "0" ]; then
        local issue="$1"
        local task="$2"

        K_ReportFailandBail "$issue" "$task"
    fi
}

function K_EstatusWarn ()
{
    # Check the exit status
    # If command fails, report Warn and continue testing

    if [ "$?" -ne "0" ]; then
        local concern="$1"
        local task="$2"
        local report="Warn"

        K_ReportStatus "$report" "$concern" "$task"
    fi
}

# K_Vercmp() returns one of the following values in the global K_KVERCMP_RET:
#   -1 if kernel version from argument $1 is older
#    0 if kernel version from argument $1 is the same as $2
#    1 if kernel version from argument $1 is newer
K_KVERCMP_RET=0
function K_Vercmp ()
{
    local ver1=$(echo $1 | sed 's/-/./')
    local ver2=$(echo $2 | sed 's/-/./')

    local ret=0
    local i=1
    while [ 1 ]; do
        local digit1=$(echo $ver1 | cut -d . -f $i)
        local digit2=$(echo $ver2 | cut -d . -f $i)

        if [ -z "$digit1" ]; then
            if [ -z "$digit2" ]; then
                ret=0
                break
            else
                ret=-1
                break
            fi
        fi

        if [ -z "$digit2" ]; then
            ret=1
            break
        fi

        if [ "$digit1" != "$digit2" ]; then
            if [ "$digit1" -lt "$digit2" ]; then
               ret=-1
               break
            fi
            ret=1
            break
        fi

        i=$((i+1))
    done
    # shellcheck disable=SC2034
    K_KVERCMP_RET=$ret
}
function K_VercmpTest ()
{
    kvercmp '2.6.32-100.el6' '2.6.32-100.el6'
    kvercmp '2.6.32-100.el6' '2.6.32-101.el6'
    kvercmp '2.6.32-101.el6' '2.6.32-100.el6'
    kvercmp '2.6.32-101.el6' '3.1.4-0.2.el7.x86_64'
    kvercmp '3.1.4-0.2.el7.x86_64' $(uname -r)
    kvercmp $(uname -r) '3.1.4-0.1.el7.x86_64'
}

# K_IsKernelRPM returns 0 in running kernel is from rpm and 1 if it is not
function K_IsKernelRPM ()
{
    rpm -qf "/boot/config-$(uname -r)" > /dev/null 2>&1
}

# K_GetRunningKernelRpmVersionRelease return the rpm version of the running kernel
# with new kernel variants using just uname -r can be tricky
# for example uname -r would output something like `5.14.0-290.el9.x86_64+rt-debug`
# therefore, trying to install kernel-rt-debug-$(uname -r) wouldn't work
function K_GetRunningKernelRpmVersionRelease ()
{
    if K_IsKernelRPM; then
        rpm -q --queryformat '%{version}-%{release}' -qf "/boot/config-$(uname -r)"
    fi
}

# returns the kernel package name of running kernel.
# Like: kernel, kernel-debug, kernel-rt, kernel-rt-debug, kernel-64k
function K_GetRunningKernelRpmName ()
{
  if K_IsKernelRPM; then
    rpm -q --queryformat '%{name}' -qf "/boot/config-$(uname -r)" | sed s/-core//
  fi
}

# returns the kernel source package name of running kernel.
# Like: kernel, kernel-rt...
function K_GetRunningKernelSrpmName ()
{
  if K_IsKernelRPM; then
    rpm -q --queryformat '%{sourcerpm}' -qf "/boot/config-$(uname -r)" | sed "s/-$(K_GetRunningKernelRpmVersionRelease).*//"
  fi
}

# Returns a nvr for a derived subpackage of the _binary rpm_
# Example:
#    For a system running kernel-64k:
#    $(K_GetRunningKernelRpmSubPackageNVR modules-internal) -> kernel-64k-modules-internal-5.14.0-291.el9
function K_GetRunningKernelRpmSubPackageNVR ()
{
  if [ -z "$1" ]; then
    echo "FAIL: missing sub-package name parameter"
    return 1
  fi

  if ! K_IsKernelRPM; then
    return
  fi

  local subpkg k_rpm k_srpm k_rpm_vr k_srpm_vr
  subpkg="$1"
  k_rpm=$(K_GetRunningKernelRpmName)
  k_rpm_vr=$(K_GetRunningKernelRpmVersionRelease)
  k_srpm=$(K_GetRunningKernelSrpmName)
  k_srpm_vr=${k_rpm_vr}

  # "SRPM subpackages" are the set of subpackages where the running kernel binary
  # does not build said subpackage, so we must install its respective SRPM's subpackage.
  #   Example: kernel-rt does not build headers, so we use kernel-headers
  declare -a srpm_subpkgs=()
  # "Debug subpackages" represent the set of subpackages that a running kernel[-.*]-debug
  # binary does not build itself, but rather its corresponding non-debug variant builds,
  # so we must install the non-debug variant's subpackage.
  #   Example: kernel-automotive-debug does not build selftests-internal, so
  #   we use kernel-automotive-selftests-internal
  declare -a debug_subpkgs=()

  # set kernel srpm/debug subpackages based on the running kernel binary
  if [[ "$k_rpm" == "kernel-debug" || \
        "$k_rpm" == "kernel-64k"* || \
        ("$k_rpm" == "kernel-rt"* && "$k_srpm" == "kernel") ]]; then
    srpm_subpkgs=(cross headers ipaclones tools debuginfo-common selftests)
  elif [[ "$k_rpm" == "kernel-automotive"* || \
          ("$k_rpm" == "kernel-rt"* && "$k_srpm" == "kernel-rt") ]]; then
    srpm_subpkgs=(cross headers ipaclones tools)
    debug_subpkgs=(debuginfo-common selftests)
  fi

  # special cases: non-unified kernel-rt & kernel-automotive must translate the kernel srpm N/VR
  if [[ "$k_rpm" == "kernel-rt"* && "$k_srpm" == "kernel-rt" ]]; then
    # e.g.: kernel-rt-4.18.0-479.rt7.268.el8 --> kernel-4.18.0-479.el8
    k_srpm="kernel"
    k_srpm_vr="${k_srpm_vr//rt[0-9]*.[0-9]*./}"
  elif [[ "$k_rpm" == "kernel-automotive"* ]]; then
    # e.g.: kernel-automotive-5.14.0-301.264.el9iv --> kernel-5.14.0-301.el9
    k_srpm="kernel"
    local X=${k_srpm_vr%.[0-9]*.el[0-9].*iv} # 5.14.0-301
    local Y=${k_srpm_vr/*.el/el}             # el9iv
    k_srpm_vr="${X}.${Y//iv}"                # 5.14.0-301.el9
  fi

  # checks if requested subpkg needs to come from the kernel srpm
  for srpm_subpkg in "${srpm_subpkgs[@]}"; do
    if [[ "${subpkg}" =~ "${srpm_subpkg}".* ]]; then
      echo "${k_srpm}-${subpkg}-${k_srpm_vr}"
      return 0
    fi
  done

  # checks if requested subpkg needs to come from the binary's non-debug variant
  # note: the running binary may already be a non-debug variant, in which case
  #       this loop effectively performs the same action as the echo statement
  #       immediately following this loop
  for debug_subpkg in "${debug_subpkgs[@]}"; do
    if [[ "${subpkg}" =~ "${debug_subpkg}".* ]]; then
      echo "${k_rpm//-debug/}-${subpkg}-${k_rpm_vr}"
      return 0
    fi
  done

  # requested subpkg is built by the running kernel binary
  echo "${k_rpm}-${subpkg}-${k_rpm_vr}"
}

function K_GetPkgMgr()
{
    if [[ -e /run/ostree-booted ]]; then
      echo rpm-ostree
    elif [[ -e /usr/bin/dnf ]]; then
      echo dnf
    else
      echo yum
    fi
}

# Usage: git_retry_clone <mandatory:repository to clone> <optional:how man times to retry> <optional: how long to wait before retry>
# e.g.: git_retry_clone https://github.com/google/someproject 5 3
# e.g.: git_retry_clone https://github.com/google/someproject
function git_retry_clone() {
    local TARGET_URL="$1"
    local RETRIES_NO="${2:-5}"
    local RETRY_DELAY="${3:-3}"
    local FUNCTION_NAME="git_retry_clone"

    # Check if TARGET_URL is empty
    if [[ -z "$TARGET_URL" ]]; then
        echo "[$FUNCTION_NAME] Error: TARGET_URL is required." >&2
        return 1
    fi

    echo "[$FUNCTION_NAME] Target URL: $TARGET_URL"
    echo "[$FUNCTION_NAME] Max Retry Attempts: $RETRIES_NO"
    echo "[$FUNCTION_NAME] Retry Delay: $RETRY_DELAY seconds"

    for i in $(seq 1 "$RETRIES_NO"); do
        if git clone "$TARGET_URL"; then
            echo "[$FUNCTION_NAME] Git clone succeeded."
            return 0 # Successful clone
        fi

        echo "[$FUNCTION_NAME] Attempt $i/$RETRIES_NO failed. Retrying in $RETRY_DELAY seconds..."
        sleep "$RETRY_DELAY"
    done

    echo "[$FUNCTION_NAME] Error: Failed to clone $TARGET_URL after $RETRIES_NO attempts." >&2
    return 1
}
# EndFile
