#!/bin/bash
export PYTHONPATH=../../../test-framework:../../../audio_tests:$PYTHONPATH
OUTPUTFILE=test.log
[ -f /tmp/test-params.sh ] && . /tmp/test-params.sh
command_arguments=""
if [ -n "${SEED+1}" ]
then
        command_arguments="$command_arguments --randomSeed $SEED"
fi
if [ -n "${SKIP_UNSUPPORTED+1}" ]
then
        command_arguments="$command_arguments --skip_unsupported"
fi
sh ../test_launcher.sh $TEST "./test.py $command_arguments $*" || exit 1
touch ${OUTPUTFILE}
rstrnt-report-log -l ${OUTPUTFILE}
