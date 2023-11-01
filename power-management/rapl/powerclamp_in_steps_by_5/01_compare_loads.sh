#!/bin/bash

energy_file="energy_test_output_"
frequency_file="frequency_test_output_"

echo -n '' > power.tmp
for x in 0 clamp_49 clamp_45 clamp_40 clamp_35 clamp_30 clamp_25 clamp_20 clamp_15 clamp_10 clamp_5 full; do
        tail -n 1 "$energy_file$x.tmp" >> power.tmp
done

number_of_tests="$(cat power.tmp|wc -l)"
echo "Found $number_of_tests resuts of tests."

echo "frequencies for these tests:"
for x in 0 clamp_49 clamp_45 clamp_40 clamp_35 clamp_30 clamp_25 clamp_20 clamp_15 clamp_10 clamp_5 full; do
        cat "$frequency_file$x.tmp"
done

./02_compare_idle_and_load.py "$number_of_tests"
