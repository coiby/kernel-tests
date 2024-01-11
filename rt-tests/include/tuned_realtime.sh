#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# TUNED_ACTION=<on|off|noop>
#   TUNED_ACTION=on
#     Activates tuned-adm with the realtime profile, and will reboot
#     the machine to ensure isolated_cores in realtime-variables.conf
#     takes effect
#   TUNED_ACTION=off
#     Deactivates any active tuned-adm profile and exits
#   TUNED_ACTION=noop
#     Does nothing, leaving the system in place
export TUNED_ACTION="${TUNED_ACTION:-on}"

# ISOLCPUS=<""|default|VALUE>
#   ISOLCPUS=default
#     When activating the realtime tuned profile, leaves whatever default
#     value is set for isolated_cores in realtime-variables.conf.  For
#     tuned >= 2.19, this isolates all cores except for the first per socket
#     for housekeeping.
#   ISOLCPUS=""
#     Deliberately setting ISOLCPUS to an empty string will ensure that
#     realtime-variables.conf sets `isolated_cores=`, so that no cores will
#     be isolated when activating the realtime tuned profile
#   ISOLCPUS=VALUE
#     Sets `isolated_cores=VALUE` in realtime-variables.conf before applying
#     the realtime tuned profile.  VALUE must be a valid CPU isolation string
[[ ! ${ISOLCPUS+x} ]] && ISOLCPUS="default"
export ISOLCPUS

function __tuned_pkg_verify ()
{
    for pkg in "tuned" "tuned-profiles-realtime" "rpmdevtools"; do
        rpm -q $pkg || $PKGMGR $pkg
        if ! rpm -q --quiet $pkg; then
            echo "Failed to install $pkg" | tee -a "$OUTPUTFILE"
            rstrnt-report-result "${TEST}/install_tuned_realtime" "FAIL" 1
            return 1
        fi
    done
}

function __disable_tuned ()
{
    echo "Disabling tuned" | tee -a "$OUTPUTFILE"
    tuned-adm off
    tuned-adm active | tee -a "$OUTPUTFILE"
}

function __enable_tuned ()
{
    if tuned-adm active | grep -q realtime; then
        echo "TuneD realtime is already active" | tee -a $OUTPUTFILE
        __check_isolated_cores || return
    fi

    echo "Enabling TuneD realtime with following isolcpus: $ISOLCPUS" | \
      tee -a "$OUTPUTFILE"
    __set_isolated_cores
    tuned-adm profile realtime
    tuned-adm active | tee -a "$OUTPUTFILE"

    sleep 3
    sync
    rstrnt-reboot
}

function __check_isolated_cores ()
{
    cur_isolcpus="$(get_isolated_cores)"
    if [ -z $ISOLCPUS ]; then
        # User requested ISOLCPUS=""
        if [ -z $cur_isolcpus ]; then
            # isolcpus is already empty, so no action required
            return 1
        else
            # isolcpus are set, so we must update tuned realtime and reboot
            return 0
        fi
    else
        # Either user requested specific isolated cores or set "default"
        if [ -z $cur_isolcpus ]; then
            # isolcpus is currently empty, so we must update tuned
            # realtime and reboot
            return 0
        else
            # the user requested some isolated cores, but some isolated
            # cores are already set; theoretically we should determine if
            # the isolated core set are different, but this library does
            # not yet support that; for now, return no action required
            return 1
        fi
    fi
}

function __set_isolated_cores ()
{
    # erase current set of isolated_cores, if any are set
    sed -i 's/^isolated_cores.*//g' /etc/tuned/realtime-variables.conf

    if [[ "${ISOLCPUS,,}" == "default" ]]; then
        declare tuned_ver=$(rpm -q tuned)
        rpmdev-vercmp "${tuned_ver//tuned-}" "2.19.0"
        if [ "$?" -eq "11" ]; then
            # For tuned >= 2.19, the default value is to use the
            # calc_isolated_cores function with 1 housekeeping core
            # per node
            # shellcheck disable=SC2016
            echo 'isolated_cores=${f:calc_isolated_cores:1}' >> /etc/tuned/realtime-variables.conf
        else
            # For tuned < 2.19, isolated_cores is commented out by
            # default, but must be set to some value in order to enable
            # tuned-realtime.  Set it to empty isolated cores since
            # none were specified by the user
            echo "isolated_cores=" >> /etc/tuned/realtime-variables.conf
        fi
    elif [ -z $ISOLCPUS ]; then
        # ISOLCPUS="", so set empty isolated_cores
        echo "isolated_cores=" >> /etc/tuned/realtime-variables.conf
    else
        # User specified isolated cores to set
        echo "isolated_cores=${ISOLCPUS}" >> /etc/tuned/realtime-variables.conf
    fi

    echo "realtime-variables.conf:" | tee -a "$OUTPUTFILE"
    tee -a "$OUTPUTFILE" < /etc/tuned/realtime-variables.conf
}

function __run_test_tuned_realtime ()
{
    if [[ "${TUNED_ACTION,,}" == "noop" ]]; then
        return 0
    fi

    echo "Activate TuneD realtime - Start Time: $(date)" | tee -a "$OUTPUTFILE"
    __tuned_pkg_verify

    if [[ "${TUNED_ACTION,,}" == "off" ]]; then
        __disable_tuned
    else
        __enable_tuned
    fi
}

# ---------- User Function ------------
function enable_tuned_realtime ()
{
    if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
        __run_test_tuned_realtime
    else
        echo "Active TuneD profile:" | tee -a "$OUTPUTFILE"
        tuned-adm active | tee -a "$OUTPUTFILE"

        echo "Current kernel cmdline:" | tee -a "$OUTPUTFILE"
        tee -a "$OUTPUTFILE" < /proc/cmdline

        if [[ "${TUNED_ACTION,,}" == "on" ]] && ! tuned-adm active | grep -q realtime; then
            echo "Failed to apply realtime tuned profile" | tee -a "$OUTPUTFILE"
            rstrnt-report-result "${TEST}/tuned_realtime" "FAIL" 1
            return 1
        fi
    fi

    [[ "${TUNED_ACTION,,}" != "noop" ]] && rstrnt-report-result "${TEST}/tuned_realtime" "PASS" 0
    echo "Activate TuneD realtime -  End Time: $(date)" | tee -a "$OUTPUTFILE"
    return 0
}
