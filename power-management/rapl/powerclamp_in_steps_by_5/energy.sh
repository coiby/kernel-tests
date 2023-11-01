#!/bin/bash -x
# $1 time for measurement

#overflow in 274877906944 = 2^38 in Intel(R) Core(TM) i7-4900MQ CPU @ 2.80GHz CPU Model=60
overflow_file="overflow"
#how often it checks for overflow. It must be a least twice between overflows to algorithm works properly
granularity=10
#on which value energy measures overflows on this CPU?
overflow_point=0

if [ -z "$1" ]; then
        time=30
        #Default is 30 secs
else
        time="$1"
fi


rapl_path="/sys/devices/virtual/powercap/intel-rapl"
rapl="$(ls -1 "$rapl_path" | grep 'intel-rapl:')"

measuring_start="$(date +%s)"
(( measuring_should_stop=measuring_start+time ))
#e1=0
#for cpu in $rapl; do
#        e_cpu="$(cat "$rapl_path/$cpu/energy_uj"*)"
#        (( e1+=e_cpu ))
#done

#save the energy for each CPU
i="0"
for cpu in $rapl; do
        e_start["$i"]="$(cat "$rapl_path/$cpu/energy_uj"*)"
        #initialize array for overflow check algorithm
        e[$i]="${e_start[$i]}"
        overflow[$i]="0"
        (( i+=1 ))
done

#wait defined time with the lowest possible load on CPUs
waitdone=0
#why 10%? It can wait the first 90% of time just adding pieces of sleep, but
#code in between of leeps needs dome time to, so it's better to check real time
#after 90% of wait. This value can be adjusted depending on the system
(( time10pct=time/10 ))
timetowait="$time"
#on which power of two overflow on this machine is?
overflowpoint="0"
while [ "$waitdone" -eq 0 ]; do
        #do the wait
        if [ "$timetowait" -le "$time10pct" ]; then
                #better to check with real date
                date_now="$(date +%s)"
                (( timetowait=measuring_should_stop-date_now))
                #let's wait 90% of the rest interval without calling date
                (( time10pct=timetowait/10 ))
        fi

        if [ "$timetowait" -gt "$granularity" ]; then
                (( timetowait-=granularity ))
                sleep "$granularity"
        else
                #better to check anyway, it's the last sleep
                date_now="$(date +%s)"
                (( timetowait=measuring_should_stop-date_now ))
                if [ "$timetowait" -gt "0" ]; then
                        sleep "$timetowait"
                fi
                waitdone="1"
        fi

        #check for overflow
        i=0
        for cpu in $rapl; do
                e_old[$i]=${e[$i]}
                e[$i]="$(cat "$rapl_path/$cpu/energy_uj"*)"
                #DEBUG
                echo "${e[$i]} -lt ${e_old[$i]}"
                if [ "${e[$i]}" -lt "${e_old[$i]}" ]; then
                        #DEBUG
                        echo "DEBUG: $overflow_point"
                        if [ "$overflow_point" -eq "0" ]; then
                                ##piece of math, explained below
                                ##using external binary bc
                                #overflow_point_base="$(echo "l(${e_old[$i]})/l(2)+1"|bc -l|sed 's/\..*//')"
                                ##using external binary dc - default on RH systems
                                overflow_point_base="$(echo "${e_old[$i]} 2/2op" |dc|wc -c)"
                                #DEBUG
                                echo "DEBUG: overflow_point_base = $overflow_point_base"
                                #much faster in shell than call dc/bc again
                                #DEBUG
                                overflow_point="$(( 2**overflow_point_base ))"
                                echo "DEBUG: overflow_point = $overflow_point"
                        fi
                        #DEBUG
                        echo "overflow $i is: ${overflow[$i]}"
                        (( overflow[i]+=overflow_point ))
                        #DEBUG
                        echo "overflow $i is: ${overflow[$i]}"
                fi
                (( i+=1 ))
        done


done

#save the energy for each CPU again
i=0
for cpu in $rapl; do
        e_end[$i]="$(cat "$rapl_path/$cpu/energy_uj"*)"
        (( i+=1))
done

#DEBUG
i=0
for cpu in $rapl; do
        echo "CPU: $cpu, END_ENERGY: ${e_end[$i]}, OVERFLOWS: ${overflow[$i]}"
        (( i+=1))
done


#save time of measurement
measuring_stop="$(date +%s)"
(( real_time=measuring_stop-measuring_start ))

#add lost values from overflows.
i=0
energy=0
for cpu in $rapl; do
        (( e[i]=e_end[i]-e_start[i]+overflow[i] ))
        (( energy+=e[i] ))
        (( i+=1))
done

#print all energies and overflows to stderr
i=0
for cpu in $rapl; do
        echo "CPU $i: ${e[$i]} uJ, with overflow ${overflow[i]} uJ" >2
        (( i+=1))
done
echo "For all CPUs: $energy uJ in $real_time s"

(( power=energy/real_time ))

echo "$power"

# explanation of the piece of math above
# Overflow occurs on whole powers of 2 (2^integer_value), because it's caused by not enough bits to
# store the value. Therefore the number should be power of 2. But we have some smalled (earlier
# number) we believe is bigger than half of the value we need. It is true if the wait_between_measures
# is small enough.
#
# The old nuber (last value before overflow) is stored in ${e_old[$i]}. So lets find out the nearest
# bigger power of two. l(${e_old[$i]}) is natural logarithm of the number (in bc syntax). It's not
# very useful, but l(${e_old[$i]})/l(2) is logarithm with base2, which gave us how many bits are
# needed to store the number (it is not integer!). So if this number is rounded up to the nearest
# integer, it's exponent we'd like to use to find the overflow value.
#
# There are more ways how to round number up, but (in C syntax) int(x+1) will do the work.
# l(${e_old[$i]})/l(2)+1 is that "x+1", than it's fed to calculator bc (-l switches on the math library)
# and sed cuts decimal point and anything after it. So we have rounded-up integer exponent.
#
# $(( 2**overflow_point_base )) founds the actual number. It doesn't make a sense to do slow call of bc
# for operation bash is able to perform. The '**' is power operator in bash.
#
# Please note it's computed just once to save load and energy to limit interference with test to minimum.
#
# Version with dc instead of bc does the same think different way.
# let's see an example:
# echo "131054 2/2op" |dc|wc -c
# dc is stack calculator with reverse polish notation so we're pushing to stack:
# 131054 2
# / (so we have exactly one bit less - 65527 on the top of stack)
# 2op (2 goes to the top, o switches output to 2-base numbers, p prints it)
# there is 1111111111110111\n on the stdout
# wc -c wounts it including trailing \n - that's why there is division by 2  - to enshort it by one bit
# number of bits needed to write the number is the value we're searchig for, because 2^number_of_bits
# is the nearest higher power of 2.

