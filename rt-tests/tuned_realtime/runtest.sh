#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Enable TMT testing for RHIVOS
. ../../automotive/include/rhivos.sh || exit 1
: "${OUTPUTFILE:=runtest.log}"

# Source rt common functions
. ../include/runtest.sh || exit 1

export TEST="rt-tests/tuned_realtime"
export ACTION="${ACTION:-on}"
[[ ! ${ISOLCPUS+x} ]] && ISOLCPUS="default"
export ISOLCPUS

function pkg_verify ()
{
    for pkg in "tuned" "tuned-profiles-realtime"; do
        rpm -q $pkg || $PKGMGR $pkg
        if ! rpm -q --quiet $pkg; then
            echo "Failed to install $pkg" | tee -a "$OUTPUTFILE"
            rstrnt-report-result "$TEST" "FAIL" 1
            exit 1
        fi
    done
}

function disable_tuned ()
{
    echo "Disabling tuned" | tee -a "$OUTPUTFILE"
    tuned-adm off
    tuned-adm active | tee -a "$OUTPUTFILE"
}

function enable_tuned ()
{
    echo "Enabling realtime tuned with following isolcpus: $ISOLCPUS" | \
      tee -a "$OUTPUTFILE"
    set_isolated_cores
    tuned-adm profile realtime
    tuned-adm active | tee -a "$OUTPUTFILE"
    rstrnt-reboot
}

function set_isolated_cores ()
{
    if [[ "${ISOLCPUS,,}" == "default" ]]; then
        # Leave default isolated_cores in realtime-variables.conf
        return 0
    elif [ -z $ISOLCPUS ]; then
        # ISOLCPUS="", so set empty isolated_cores
        sed -i 's/^isolated_cores.*/isolated_cores=/g' \
          /etc/tuned/realtime-variables.conf
    else
        # User specified isolated cores to set
        sed -i "s/^isolated_cores.*/isolated_cores=${ISOLCPUS}/g" \
          /etc/tuned/realtime-variables.conf
    fi

    echo "realtime-variables.conf:" | tee -a "$OUTPUTFILE"
    tee -a "$OUTPUTFILE" < /etc/tuned/realtime-variables.conf
}

function run_test ()
{
    pkg_verify

    if [[ "${ACTION,,}" == "off" ]]; then
        disable_tuned
    else
        enable_tuned
    fi
}

# ---------- Start Test -------------
if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
    echo "Test Start Time: $(date)" | tee -a "$OUTPUTFILE"

    if ! kernel_automotive; then
        # Install standard realtime packages if kernel-rt is running, otherwise
        # SKIP this test, it's required for all rt-tests.
        rt_env_setup
    fi
    run_test
else
    # System has reboot, implying we have applied the realtime tuned
    # profile; verify the active profile and print the kernel cmdline
    # for debugging
    echo "Active tuned profile:" | tee -a "$OUTPUTFILE"
    tuned-adm active | tee -a "$OUTPUTFILE"
    echo "Current kernel cmdline:" | tee -a "$OUTPUTFILE"
    tee -a "$OUTPUTFILE" < /proc/cmdline

    if ! tuned-adm active | grep -q realtime; then
        echo "Failed to apply realtime tuned profile" | tee -a "$OUTPUTFILE"
        rstrnt-report-result "$TEST" "FAIL" 1
        exit 1
    fi
fi

rstrnt-report-result "$TEST" "PASS" 0
echo "Test End Time: $(date)" | tee -a "$OUTPUTFILE"
exit 0
