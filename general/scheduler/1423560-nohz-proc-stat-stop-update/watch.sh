#!/bin/bash

taskset -c 0 grep ^cpu /proc/stat  | grep -wv -e ^cpu  -e ^cpu0 -e ^cpu1 > stat_old.log
awk '{print $2" "$4}' stat_old.log > stat_old_f.log

sleep_time=5
loop=$((RUN_TIME / sleep_time))

nr_cpu=$(cat /proc/cpuinfo | grep -w ^processor | wc -l)
max=$((nr_cpu - 1))

sleep $sleep_time
while ((loop --)); do
	ps -C stress -o psr,pcpu,stime,class,pri,cputime,pid,args 2>&1 | sort -n | grep -wv '0\.0' > ps_new.log
	taskset -c 0 grep ^cpu /proc/stat  | grep -wv -e ^cpu  -e ^cpu0 -e ^cpu1 > stat_new.log
	awk '{print $2" "$4" "$5}' stat_new.log > stat_new_f.log
	awk '
	{
		getline l < "stat_new_f.log";
		getline fl < "stat_new.log";
		if ( l == $0) {
			printf("%s bad(unchange): %s\n", systime(), fl)
			printf("%s bad(unchange): %s\n", systime(), fl) >> "cpu"(NR+1)
		} else {
		printf("%s good(change): %s\n", systime(), fl)
		printf("%s good(change): %s\n", systime(), fl) >> "cpu"(NR+1)
	}
}' stat_old_f.log
\cp ps_new.log ps_old.log
\cp stat_new.log stat_old.log
\cp stat_new_f.log stat_old_f.log
echo $(date +%s) ...
for log in $(seq 2 $max); do
	bad_nr=$(grep bad cpu$log | wc -l | awk '{print $1}')
	if ((bad_nr > 5)); then
		# shellcheck disable=SC2034
		for rep in $(seq 1 10); do
			egrep cpu$log /proc/stat
			sleep 5
		done
		exit 1
	fi
done
sleep $sleep_time
done
exit 0

