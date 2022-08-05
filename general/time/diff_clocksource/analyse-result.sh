#!/bin/bash -x

exec 3<./myfile.txt

read -u3 pre
while read -u3 next; do
    echo =====
    echo pre=$pre;
    echo next=$next;
    expr  $next \> $pre

    if [ $? = 0 ]; then
        pre=$next
    else
        echo $pre $next | tee -a $OUTPUTFILE
        echo "Failed" | tee -a $OUTPUTFILE
    fi
done
