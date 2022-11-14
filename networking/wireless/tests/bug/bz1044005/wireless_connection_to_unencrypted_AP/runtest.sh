#!/bin/bash
export PYTHONPATH=../../../../test-framework:../../../../wireless_tests:$PYTHONPATH
. /tmp/test-params.sh
rhts-run-simple-test "$TEST" "./test.py $*"
rhts-submit-log -l /var/log/wpa_supplicant.log
rhts-submit-log -l ./test.log
rhts-submit-log -l /var/log/messages

