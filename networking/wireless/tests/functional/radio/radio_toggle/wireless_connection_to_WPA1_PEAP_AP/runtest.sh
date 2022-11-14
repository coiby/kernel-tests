#!/bin/bash
export PYTHONPATH=../../../../../test-framework:../../../../../wireless_tests:$PYTHONPATH
. /tmp/test-params.sh
sh ../../../../../test-framework/test_launcher.sh "$TEST" "./test.py $*"
rhts-submit-log -l /var/log/wpa_supplicant.log
rhts-submit-log -l ./test.log
rhts-submit-log -l /var/log/messages
