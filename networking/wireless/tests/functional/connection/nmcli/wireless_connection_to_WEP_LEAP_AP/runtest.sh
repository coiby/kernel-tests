#!/bin/bash

# add path to test_launcher script
export PATH=../../../../../common/:$PATH
# add path to base and functional modules
export PYTHONPATH=../../../../../common/:../../../../../tests/:$PYTHONPATH

if [ -z "${PING_ADDRESS}" ]; then
	sh test_launcher.sh "$TEST" "test.py $*"
else
	sh test_launcher.sh "$TEST" "test.py --pingAddress $PING_ADDRESS"
fi

rhts-submit-log -l /var/log/wpa_supplicant.log --port=8081
rhts-submit-log -l ./test.log --port=8081
rhts-submit-log -l /var/log/messages --port=8081
