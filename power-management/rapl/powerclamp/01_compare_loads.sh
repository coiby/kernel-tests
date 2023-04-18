#!/bin/bash

number_of_tests="$(cat power.tmp | wc -l)"
echo "Found $number_of_tests resuts of tests."

./02_compare_idle_and_load.sh "$number_of_tests"
