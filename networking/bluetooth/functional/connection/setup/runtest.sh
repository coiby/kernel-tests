#!/bin/bash
rhts-run-simple-test $TEST "./test.sh $@"
rhts-submit-log -l ./test.log
rhts-submit-log -l /var/log/messages
