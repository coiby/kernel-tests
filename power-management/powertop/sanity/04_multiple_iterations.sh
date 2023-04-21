#!/bin/bash
filename_base="foo"
filename_suffix="csv"
iterations=10

rm "${filename_base}-"*".$filename_suffix"
powertop --iteration="$iterations" --csv="$filename_base.$filename_suffix"
retval="$?"

#if [ "$retval" != 0 ]; then
#        echo "Warning: powertop returned $retval"
#        generate warning
#        exit 0
#fi

files="$(ls -1 "${filename_base}-"*".$filename_suffix" 2>/dev/null | wc -l)"
echo "$files"
if [ "$files" -eq "$iterations" ]; then
        echo "O.K."
        exit 0
else
        echo "Powertop hasn't generated right number of output files."
        echo "iterations = $iterations"
        echo "ls:"
        ls -l "$filename_base*"
        exit 1
fi
