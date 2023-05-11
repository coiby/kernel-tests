# Enable TMT testing for RHIVOS
. ../../automotive/include/include.sh
declare -F kernel_automotive && kernel_automotive && is_rhivos=1 || is_rhivos=0

if ! (($is_rhivos)); then
	# Include rhts environment
	. /usr/bin/rhts-environment.sh || exit 1
fi

#!/bin/bash

command_arguments=""

if [ -n "${SEED+1}" ]; then
	command_arguments="$command_arguments --randomSeed $SEED"
fi

if [ -n "${PREFERRED_COMMAND+1}" ]; then
	command_arguments="$command_arguments --preferredCommand $PREFERRED_COMMAND"
fi

if [ -n "${TEST_INTERFACE+1}" ]; then
	command_arguments="$command_arguments --testInterface $TEST_INTERFACE"
fi

sh test_launcher.sh "$TEST" "test.py $command_arguments $*"
rhts-submit-log -l /var/log/wpa_supplicant.log --port=8081
rhts-submit-log -l ./test.log --port=8081
rhts-submit-log -l /var/log/messages --port=8081
