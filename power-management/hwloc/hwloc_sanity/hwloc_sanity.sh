#!/bin/bash

divide1k_and_round() {
        # $1 integer number
        # output is round($1/1024)
        #
        # expr does the integer division itself, so adding half of divisor is enough
        # to handle rounding
        expr \( "$1" + 512 \) / 1024
}

to_higher_suffix() {
        # $1 number with or without suffix (k, K, M, G, T)
        # output is the same number divided by 1024 and rounded to the nearest integer
        # with proper suffix. It may be 0, if input is < 512.

        num="$(echo "$1" | sed 's/[^0-9]//g')"
        num_div="$(divide1k_and_round "$num")"
        # Linux and utilities in Linux are using SI-incorrect suffix K for kilo
        # so let's convert k to K
        suffix="$(echo "$1" | sed 's/[^a-zA-Z]//g' | tr 'a-z' 'A-Z')"
        case "$suffix" in
                '' )
                        # No suffix
                        echo "${num_div}K"
                        ;;
                K )
                        # kilo
                        echo "${num_div}M"
                        ;;
                M )
                        # Mega
                        echo "${num_div}G"
                        ;;
                G )
                        # Giga
                        echo "${num_div}T"
                        ;;
                T )
                        # Tera
                        echo "${num_div}P"
                        ;;
                * )
                        echo "${num_div}WRONG_SUFFIX"
                        ;;
        esac
}


# Obtain some information of the system.
echo "Information obtained directly from the system."
echo "=============================================="
mem_strg="$(cat /proc/meminfo | grep '^MemTotal:')"
echo "$mem_strg"
# s/[^0-9]*//g --- remove everything except numbers
# s/$/\/2^20 --- kB -> GB
# +0.5/' .... sed 's/\..*//' --- ugly way of rounding the number correctly
mem="$(echo "$mem_strg" | sed 's/[^0-9]*//g;s/$/\/2^20+0.5/' | bc -l | sed 's/\..*//')"
echo "Memory: $mem GB"

# $(echo -ne "\t") --- ugly way how to obtain a <tab> character acceptable for grep
maxcpu="$(cat /proc/cpuinfo | grep "^processor$(echo -ne "\t"):" | sed 's/.*: //' | tail -n 1)"
echo "Max CPU number: $maxcpu"

l1dcache="$(lscpu | grep "^L1d cache:" | sed 's/.*: *//')"
l1dcache_alt="$(to_higher_suffix "$l1dcache")"
l1icache="$(lscpu | grep "^L1i cache:" | sed 's/.*: *//')"
l1icache_alt="$(to_higher_suffix "$l1icache")"
l2cache="$(lscpu | grep "^L2 cache:" | sed 's/.*: *//')"
l2cache_alt="$(to_higher_suffix "$l2cache")"
l3cache="$(lscpu | grep "^L3 cache:" | sed 's/.*: *//')"
l3cache_alt="$(to_higher_suffix "$l3cache")"
echo "Caches: L1d $l1dcache ($l1dcache_alt), L1i $l1icache ($l1icache_alt), L2 $l2cache ($l2cache_alt), L3 $l3cache ($l3cache_alt)"

numanodes="$(lscpu | grep 'NUMA node(s):' | sed "s/^NUMA node(s): *//")"
echo "numa nodes: $numanodes"


# Extract the same information from the output of lstopo
echo
echo "Information obtained from hwloc/lstopo.       "
echo "=============================================="
lstopo_output="$(lstopo-no-graphics)"

mem_lstopo="$(echo "$lstopo_output" | grep "^Machine (" | grep "GB" | sed 's/^Machine (//;s/GB.*//')"
if [ -z "$mem_lstopo" ]; then
        # It's an old system with memory denoted in MB
        # No need pro precision here
        mem_lstopo_MB="$(echo "$lstopo_output" | grep "^Machine (" | grep "MB" | sed 's/^Machine (//;s/MB.*/M/')"
        mem_lstopo="$(to_higher_suffix "$mem_lstopo_MB" | sed 's/G//')"
fi
echo "Memory: $mem_lstopo GB"

maxcpu_lstopo="$(echo "$lstopo_output" | grep 'PU L#' | sed 's/^.* PU L#\([0-9]*\) .*/\1/' | sort -n | tail -n 1 )"
echo "max CPU num: $maxcpu_lstopo"

l1dcache_lstopo="$(echo "$lstopo_output" | grep 'L1d' | sed 's/.* L1d L#[0-9]* (\([0-9]*[kKmMgG]\)B).*/\1/' | uniq)"
l1icache_lstopo="$(echo "$lstopo_output" | grep 'L1i' | sed 's/.* L1i L#[0-9]* (\([0-9]*[kKmMgG]\)B).*/\1/' | uniq)"
l2cache_lstopo="$(echo "$lstopo_output" | grep 'L2' | sed 's/.* L2 L#[0-9]* (\([0-9]*[kKmMgG]\)B).*/\1/' | uniq)"
l3cache_lstopo="$(echo "$lstopo_output" | grep ' L3 ' | sed 's/.* L3 L#[0-9]* (\([0-9]*[kKmMgG]\)B).*/\1/' | uniq)"

echo "Caches: L1d $l1dcache_lstopo, L1i $l1icache_lstopo, L2 $l2cache_lstopo, L3 $l3cache_lstopo"

numanodes_lstopo="$(echo "$lstopo_output" | grep NUMANode | wc -l)"
if [ "$numanodes_lstopo" -eq "0" ]; then
        # lstopo doesn't print any numa nodes when there is just one (non-NUMA system)
        # but lscpu prints one
        numanodes_lstopo=1
fi
echo "numa nodes: $numanodes_lstopo"

# Compare the values
echo
echo "Data comparation.                             "
echo "=============================================="
# pass
status=0

for variable in mem maxcpu l1dcache l1icache l2cache l3cache numanodes; do
        # This is classic if - then - else. The eval is used for varying the variable name only.
        # unrolled equivalent code looks like
        # if [ var != var_lstopo -o var_alt != var_lstopo ]; then
        #       echo "Check var: PASS"
        # else
        #       status=1
        #       echo "Check var: FAIL"
        # fi
        check_cmd="if [ \"\$$variable\" = \"\$${variable}_lstopo\" -o \"\$${variable}_alt\" = \"\$${variable}_lstopo\" ]; then echo \"Check $variable: PASS\"; else status=1; echo \"Check $variable: FAIL ; #\$$variable# != #\$${variable}_lstopo#\"; fi"
###        check_cmd="if [ \"\$$variable\" != \"\$${variable}_lstopo\" -o \"\$${variable}_alt\" != \"\$${variable}_lstopo\" ]; then echo \"Check $variable: PASS\"; else status=1; echo \"Check $variable: FAIL\"; fi"
        eval "$check_cmd"
done

echo
echo "SUMMARY                                       "
echo "=============================================="
if [ "$status" = "0" ]; then
        echo "PASS"
else
        echo "FAIL"
fi

exit "$status"

