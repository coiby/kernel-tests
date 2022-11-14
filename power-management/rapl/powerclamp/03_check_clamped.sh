#!/bin/bash

###############################################################################
# Uses data (in file power.tmp - originally from perf) from previous run.
# Checks if reported power consumption during clamped (to 51%) full load
# is approx. average between idle and unclamped full load. Loads should
# be in ascending order.
#
# Accepts two parameters - the first is how many records should be in file
# (default = 3), the second is the file (default = "power.tmp").
#
# For more than 3 parameters evenly distribution is assumed now. Like
# idle, 1/3, 2/3, full or so.
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

# The real power1 should be equal to the computed power2. There is some range for
# rounding errors, some daemons started incidentally during the idle run and things
# like that, so the comparison is done this way:
# power2 * 100 / acceptable_error < power1 < power2 * acceptable_error / 100
acceptable_error=120

warn_file="warn.tmp"


if [ "$1" ]; then
        records="$1"
else
        records=3
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


#@@#

error=0
err=0
declare -a data
i=0
while read pwr; do
        data[$i]="$pwr"
        (( i+=1 ))
done < "$data_file"

base="${data[0]}"
step="$(( (data[records - 1] - base)/(records - 1) ))"
echo "Idle load: $base uJ"
echo "Full load: $((data[records - 1])) uJ"

for i in `seq 0 "$((records - 1))"`; do
        check="${data[i]}"
        if [ "$records" -eq 3 ]; then
                echo "Middle load is: $check uJ"
        else
                echo "$i-th load is: $check uJ"
        fi

        if (( check > (base + i*step) * acceptable_error / 100 )); then
                err=1
        fi
        if (( check < (base + i*step) * 100 / acceptable_error )); then
                err=1
        fi
        if [ "$err" = 1 ]; then
                echo 'Power consumption during clamp is too far from expected values. ',
                echo "$check should be approx. equal to $((base + i*step))"
                (( error+=1 ))
                err=0
        else
                echo "O.K. check, is approx. equal to $((base + i*step)) within acceptable error range."
        fi
done

if [ "$error" -gt 0 ]; then
        echo
        echo "An error occured. But the single fail doesn't mean hard no-go."
        echo "It's probably a problem. But if it fails in a few percents of runs"
        echo "on the same machine, it can be due to same load from test system or"
        echo "unexpected run of daemon also."
else
        echo
        echo "PASSED"
fi

exit "$error"
