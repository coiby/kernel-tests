#!/bin/bash
export PYTHONPATH=../../../test-framework:../../../audio_tests:$PYTHONPATH
. /tmp/test-params.sh
command_arguments=""
if [ -n "${SEED+1}" ]
then
    command_arguments="$command_arguments --randomSeed $SEED"
fi

if [ -n "${SKIP_CONTROLS+1}" ]
then
    controls=(${SKIP_CONTROLS//,/ })
    for control in "${controls[@]}"
    do
        command_arguments="$command_arguments --skip-control $control"
    done
fi

if [ -z "${DISABLE_ZERO+1}" ]
then
    command_arguments="$command_arguments --confirm-zero"
fi

if [ -n "${TEST_FREQUENCIES+1}" ]
then
    frequencies=(${TEST_FREQUENCIES//,/ })
    for frequency in "${frequencies[@]}"
    do
        command_arguments="$command_arguments --test-frequency $frequency"
    done
fi
sh ../../../test-framework/test_launcher.sh $TEST "./test.py $command_arguments $*"
rhts-submit-log -l ./test.log
