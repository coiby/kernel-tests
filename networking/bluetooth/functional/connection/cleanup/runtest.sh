#!/bin/bash
export PYTHONPATH=../../../../test-framework:../../../../bluetooth_tests:$PYTHONPATH
. /tmp/test-params.sh
command_arguments=""
if [ -n "${SEED+1}" ]
then
command_arguments="$command_arguments --randomSeed $SEED"
fi
if [ -n "${MAC+1}" ]
then
command_arguments="$command_arguments --MACaddress $MAC"
fi
rhts-run-simple-test $TEST "./test.py $command_arguments $@"
rhts-submit-log -l ./test.log
rhts-submit-log -l /var/log/messages
