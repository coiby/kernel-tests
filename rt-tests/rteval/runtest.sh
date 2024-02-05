#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright Red Hat, Inc
#
#   SPDX-License-Identifier: GPL-3.0-or-later
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Source rt common functions
. ../include/runtest.sh || exit 1

# User Parameters
: "${DURATION:=900}"
: "${LATCHECK:=1}"
: "${MAXLAT:=150}"
: "${STDDEVLAT:=5}"
: "${LOADS_CPUS:=}"
: "${MEASURE_CPUS:=}"

# Vars
export TEST="rt-tests/rteval"


function measure_latency()
{
    which bc >/dev/null || $PKGMGR bc

    # get the max and standard deviation latency from rteval output
    declare max_lat stddev_lat
    max_lat=$(grep --text -A 11 'System:' $OUTPUTFILE | \
              grep 'Max:' | awk -F ':' '{print $2}' | xargs)
    max_lat=${max_lat%us}
    stddev_lat=$(grep --text -A 11 'System:' $OUTPUTFILE | \
                 grep 'Std.dev:' | awk -F ':' '{print $2}' | xargs)
    stddev_lat=${stddev_lat%us}

    log "Performing latency threshold check:"
    log "-> rteval max/stddev lat was: ${max_lat}us / ${stddev_lat}us"
    log "-> max/stddev lat should be under: ${MAXLAT}us / ${STDDEVLAT}us"

    # verify the max and stddev latency fall within tolerable range
    run "(( $(echo "$max_lat < $MAXLAT" | bc -l) ))"
    run "(( $(echo "$stddev_lat < $STDDEVLAT" | bc -l) ))"
}

function test_setup ()
{
    if [ "$RSTRNT_REBOOTCOUNT" -eq 0 ]; then
        rt_env_setup
        ! cki_is_kernel_automotive && enable_tuned_realtime
    fi

    phase_start_setup

    isolated_cpus=$(get_isolated_cores)
    housekeeping_cpus=$(get_housekeeping_cores)

    log "System isolated cores: $isolated_cpus"
    log "System housekeeping cores: $housekeeping_cpus"

    FLAG_LOADS=""
    FLAG_MEASURE=""

    if [ -n "$LOADS_CPUS" ]; then
        if [[ "$LOADS_CPUS" == "housekeeping" ]]; then
            FLAG_LOADS="--loads-cpulist $housekeeping_cpus"
        elif [[ "$LOADS_CPUS" == "isolated" ]]; then
            FLAG_LOADS="--loads-cpulist $isolated_cpus"
        else
            FLAG_LOADS="--loads-cpulist $LOADS_CPUS"
        fi
    fi

    if [ -n "$MEASURE_CPUS" ]; then
        if [[ "$MEASURE_CPUS" == "housekeeping" ]]; then
            FLAG_MEASURE="--measurement-cpulist $housekeeping_cpus"
        elif [[ "$MEASURE_CPUS" == "isolated" ]]; then
            FLAG_MEASURE="--measurement-cpulist $isolated_cpus"
        else
            FLAG_MEASURE="--measurement-cpulist $MEASURE_CPUS"
        fi
    fi

    # Check if loads or measurement cpulist were set to an empty string,
    # indicating there were no system isolated cores despite being
    # requested. If so, unset both parameters.  In the event the other
    # parameter utilizes all CPUs on the host, rteval will throw an IndexError
    if [[ "$FLAG_LOADS" == "--loads-cpulist " ||\
          "$FLAG_MEASURE" == "--measurement-cpulist " ]]; then
        log_warn "No isolated cores are set on the system despite being requested"\
                 "for either load or measurement CPUs."
        log_warn "Unsetting both load and measurement CPU parameters to avoid"\
                 "a potential IndexError."
        FLAG_LOADS=""
        FLAG_MEASURE=""
        report_result "${TEST}/no-isolcpus" "WARN" 1
    fi

    export FLAG_LOADS FLAG_MEASURE

    phase_end
}

function test_run ()
{
    phase_start "${TEST}" FAIL

    if ! mount | grep -q debugfs; then
        log "Mounting debugfs to /sys/kernel/debug"
        run -l "mount -t debugfs none /sys/kernel/debug"
    fi

    # let's rock'n'roll
    run "rteval --duration=$DURATION -D -L $FLAG_LOADS $FLAG_MEASURE"

    find . -maxdepth 1 -name "rteval-????????-*.tar.bz2" -print |
        while IFS= read -r rep; do
            log "Attaching report: $rep"
            rstrnt-report-log -l $rep
        done

    # perform a max and stddev latency check if requested
    if [ $LATCHECK -eq 1 ]; then
        measure_latency
    fi

    phase_end
}


# ---------- Start Test -------------
test_setup
test_run
