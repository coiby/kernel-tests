#!/bin/bash
export PYTHONPATH=../../libs:../helper-code:$PYTHONPATH
. /tmp/test-params.sh
rhts-run-simple-test "$TEST"/"$WIFI_DEVICE" "./test.py"
rhts-submit-log -l /var/log/wpa_supplicant.log
