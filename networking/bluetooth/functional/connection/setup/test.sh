#!/bin/bash
export PYTHONPATH=../../../../wireless/common:../../../../bluetooth:$PYTHONPATH
[ -f /tmp/test-params.sh ] && . /tmp/test-params.sh

command_arguments=""
if [ -n "${SEED+1}" ]
then
command_arguments="$command_arguments --randomSeed $SEED"
fi
if [ -n "${PRESET+1}" ]
then
command_arguments="$command_arguments --connectionPreset $PRESET"
fi
if [ -n "${MAC+1}" ]
then
command_arguments="$command_arguments --customMAC $MAC"
fi
if [ -n "${BLE+1}" ]
then
command_arguments="$command_arguments --customLE"
fi
./test.py $command_arguments $@
