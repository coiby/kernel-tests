#!/bin/bash
export PYTHONPATH=../../../test-framework:../../../audio_tests:$PYTHONPATH
. /tmp/test-params.sh
command_arguments=""
if [ -n "${SEED+1}" ]
then
command_arguments="$command_arguments --randomSeed $SEED"
fi
sh ../../../test-framework/test_launcher.sh $TEST "./test.py $command_arguments $@"
rhts-submit-log -l ./test.log
