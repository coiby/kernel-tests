#!/bin/bash

outputs="$(cat perf_test_output_* | grep Joules | sed 's/Joules.*$//;s/^ *//')"

echo "$outputs" > power.tmp

number_of_tests="$(echo "$outputs"|wc -l)"
echo "Found $number_of_tests resuts of tests."

./02_compare_idle_and_load.py "$number_of_tests"
