#!/bin/sh

. /usr/bin/rhts_environment.sh

test_string="./average_amplitude_calculator.py"

# Check for FILE command line argument
if [ -n "${FILE+1}" ]
then
    test_string="$test_string --file $FILE"
fi

echo $test_string

rhts-run-simple-test $TEST "$test_string"
