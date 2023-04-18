#!/bin/bash
# $1 timeout
# $2 threads of load

#echo "getting timeout $1 and threadno $2"
for a in `seq 1 "$2"`; do
        #echo "starting load thead $a"
        ./load1.sh "$1" &
done
