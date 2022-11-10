#!/bin/bash
export PYTHONPATH=../../../../test-framework:../../../../bluetooth_tests:$PYTHONPATH
[ -f /tmp/test-params.sh ] && . /tmp/test-params.sh

sh ../../../../test-framework/test_launcher.sh $TEST "./test-server.py $@"
