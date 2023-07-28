#!/bin/bash
export PYTHONPATH=../../../test-framework:../../../audio_tests:$PYTHONPATH
OUTPUTFILE=test.log
[ -f /tmp/test-params.sh ] && . /tmp/test-params.sh
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
sh ../test_launcher.sh $TEST "./test.py $command_arguments $*" || exit 1
touch ${OUTPUTFILE}
rstrnt-report-log -l ${OUTPUTFILE}
