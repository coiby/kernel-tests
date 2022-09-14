#!/bin/bash
pid=$1
utime=0
stime=0
old_u=0
old_s=0
old_dtu=0
old_dts=0
dtu=0
dts=0

if test -z "$pid"; then
	echo $(date): Spurious executing $0, exit directly ....
	pstree -nlp $$
	ps -p $$ -o time,pid,ppid,etimes,args
	exit 0
fi

val=$(awk '{print $14,$15}' /proc/$pid/stat)
old_u=$(echo $val | awk '{print $1}')
old_s=$(echo $val | awk '{print $2}')
sleep 1
val=$(awk '{print $14,$15}' /proc/$pid/stat)
utime=$(echo $val | awk '{print $1}')
stime=$(echo $val | awk '{print $2}')
dtu="$(echo "$utime-$old_u" | bc)"
dts="$(echo "$stime-$old_s" | bc)"
sleep 1

printf "%s\t%s\t%s\t%s\t%s\t%s\n" Date Utime Stime DeltaU DeltaS DeltaDeltaS
while true; do
	old_u=$utime
	old_s=$stime
	old_dtu=$dtu
	old_dts=$dts
	val=$(awk '{print $14,$15}' /proc/$pid/stat)
	[ $? -ne 0 ] && echo "process:$pid not found" && break
	utime=$(echo $val | awk '{print $1}')
	stime=$(echo $val | awk '{print $2}')
	dtu="$(echo "$utime-$old_u" | bc)"
	dts="$(echo "$stime-$old_s" | bc)"

	delta=$(echo "$dts-$old_dts"|bc)
	((delta < 0)) && delta=$((-delta))
	((delta > 15)) && echo $delta >> FAILED
	printf "%s\t%ld\t%ld\t%ld\t%ld\t%ld\n" "$(date)" $utime $stime "$dtu" "$dts" "$delta"
	sleep 1
	test -f /mnt/bz1511040_done && break
done
