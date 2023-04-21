#!/bin/bash
filename="foo.html"

rm "$filename"
powertop --html="$filename"
retval="$?"

#if [ "$retval" != 0 ]; then
#        echo "Warning: powertop returned $retval"
#        generate warning
#        exit 0
#fi

if [ -f "$filename" ]; then
        echo "O.K."
        exit 0
else
        echo "powertop hasn't generated output file."
        exit 1
fi
