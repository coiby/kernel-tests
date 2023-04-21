#!/bin/bash
test_length="30"
start="$(date "+%s")"
powertop --time="$test_length" --csv
retval="$?"
stop="$(date "+%s")"

duration="$((stop - start))"
echo "Measured duration of the test was $duration s, while $test_length s was sett_length="30""

#if [ "$retval" != 0 ]; then
#        echo "Warning: powertop returned $retval"
#        generate warning
#        exit 0
#fi

if [ "$duration" -le "35" -a "$duration" -ge "29" ]; then
        #it needs some time to start and stop, so +1 or +2 seconds are usual
        echo "O.K."
        exit 0
else
        echo "Real and wanted time doesn't match."
        exit 1
fi
