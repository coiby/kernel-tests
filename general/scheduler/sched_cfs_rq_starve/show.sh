#!/bin/bash
for p in $(ps -C cputest -o pid | sed -n '1!p'); do
	a=$(find /proc/$p/ -maxdepth 1 -name schedstat -exec awk '{print $1}' {} \;)
	ps -p $p --no-headers -o time,etimes,comm:8,stat,psr,pid | awk -v a=$a '{gsub($0, $0$a);print $0,a}'
done | sort -k6 -n -r

