#!/bin/bash

###############################################################################
# Uses data (in file power.tmp - originally from turbostat) from previous run.
# Checks if reported power consumption matches during idle is not significantly
# bigger than under load. Loads should be in ascending order.
#
# Accepts two parameters - the first is how many records should be in file
# (default = 2), the second is the file (default = "power.tmp").
#
# The single fail doesn't mean hard no-go.
#
# If it fails, it's probably a problem. But if it fails in a few percents of runs
# (on the same machine), It can be due to same load from test system or unexpected
# run of daemon also.
#
# Author:  Erik Hamera alias lhc
# contact: lhc (at) redhat (dot) com
#          ehamera (at) redhat (dot) com
# License: GNU GPL
###############################################################################

power_file="power.tmp"

#Power1 should be lower, than power2, but there is some range for rounding errors,
#Some daemons may start incidentally when there was expected idle run and things like
#that. So the comparison is done in this way: ( power1 < power2 * acceptable_error/100 )
acceptable_error=120

warn_file="warn.tmp"


if [ "$1" ]; then
        records="$1"
else
        records=2
fi


if [ "$2" ]; then
        data_file="$2"
else
        data_file="power.tmp"
fi


if ! [ -f "$data_file" ]; then
        echo "No datafile - maybe not an error, just HW isn't supporting reading of power"
        echo "No datafile - maybe not an error, just HW isn't supporting reading of power" >> "$warn_file"
        exit
fi


if [ "$(cat "$data_file" | wc -l)" -lt "$records" ]; then
        echo 'Not enough records in datafile'
        echo 'Not enough records in datafile' >> "$warn_file"
        exit
fi


error=0
prev_pwr=-1
while read pwr; do
        if [ "$prev_pwr" -gt "-1" ]; then
                if (( prev_pwr*100 > pwr*acceptable_error )); then
                        echo "ERROR: $prev_pwr is higher than $pwr * $acceptable_error/100 (acceptable error) when lower is expected."
                (( error+=1 ))
                else
                        echo "O.K. $prev_pwr is lower than $pwr * $acceptable_error/100 (acceptable error)."
                fi
        fi
        prev_pwr="$pwr"
done < "$data_file"


if [ "$error" -gt 0 ]; then
        echo
        echo "An error occured. But the single fail doesn't mean hard no-go."
        echo "It's probably a problem. But if it fails in a few percents of runs"
        echo "on the same machine, it can be due to same load from test system or"
        echo "unexpected run of daemon also."
else
        echo
        echo "PASSED - logged power values are in ascending order (within defined error range", acceptable_error, ")."
fi

exit "$error"
