#!/bin/bash
export PYTHONPATH=../../../../test-framework:../../../../wireless_tests:$PYTHONPATH
. /tmp/test-params.sh
# crda gets installed as a dependency but the system needs a reboot before the
# database is read correctly
if [ "$REBOOTCOUNT" == 0 ]
then
    rhts-reboot
fi
sh ../../../../test-framework/test_launcher.sh "$TEST" "./test.py $*"
rhts-submit-log -l /var/log/wpa_supplicant.log
rhts-submit-log -l ./test.log
rhts-submit-log -l /var/log/messages
