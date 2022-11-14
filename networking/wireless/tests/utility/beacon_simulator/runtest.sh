#!/bin/bash
export PYTHONPATH=../../../test-framework:../../../wireless_tests:$PYTHONPATH
. /tmp/test-params.sh
command_arguments=""
if [ -n "${SEED+1}" ]
then
command_arguments="$command_arguments --randomSeed $SEED"
fi
if [ -n "${COUNT+1}" ]
then
command_arguments="$command_arguments --count $COUNT"
fi
if [ -n "${NUMBER_OF_SSIDS+1}" ]
then
command_arguments="$command_arguments --number_of_ssids $NUMBER_OF_SSIDS"
fi
if [ -n "${INCREMENT_BSSID+1}" ]
then
command_arguments="$command_arguments --increment_bssid"
fi
if [ -n "${STARTING_BSSID+1}" ]
then
command_arguments="$command_arguments --starting_bssid $STARTING_BSSID"
fi
if [ -n "${INCREMENT_SOURCE+1}" ]
then
command_arguments="$command_arguments --increment_source"
fi
if [ -n "${STARTING_SOURCE+1}" ]
then
command_arguments="$command_arguments --starting_source $STARTING_SOURCE"
fi
if [ -n "${INTERFACE+1}" ]
then
command_arguments="$command_arguments --interface $INTERFACE"
fi
if [ -n "${FORCE+1}" ]
then
command_arguments="$command_arguments --force"
fi
rhts-run-simple-test "$TEST" "./beacon_simulator.py $command_arguments $*"
rhts-submit-log -l ./test.log
