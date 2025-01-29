#!/bin/bash
#
# Automotive does not support hugtblfs and mm:run_vmtests.sh requires it. However not all the subtests do.
# In order to get to gup_test,  and mrelease_test I need to bypass the check and run the tests that do not require hugtblfs support.
# Test is regression of https://bugzilla.redhat.com/show_bug.cgi?id=2073217 for risk assesment https://issues.redhat.com/browse/VROOM-20044.
# Also see VROOM-21586 for process_mrelease.
#
# === GUP test ===
# get_user_pages_fast
# Description
# Attempt to pin user pages in memory without taking mm->mmap_lock. If not successful, it will fall back to taking the lock and calling get_user_pages().
# Returns number of pages pinned. This may be fewer than the number requested. If nr_pages is 0 or negative, returns 0. If no pages were pinned, returns -errno.
# For more information see https://www.kernel.org/doc/html/next/core-api/mm-api.html.
#
# pin_user_pages_fast
# Description
# FOLL_PIN is internal to gup, meaning that it should not appear at the gup call sites. This allows the associated wrapper functions (pin_user_pages*() and others)
# to set the correct combination of these flags, and to check for problems as well. For more information see https://www.kernel.org/doc/html/next/core-api/pin_user_pages.html.
#
# The tests for benchmark will return the time taken to do both retrieval and placement of pages.
#
# === process_mrelease ===
# DESCRIPTION
#   The process_mrelease() system call is used to free the memory of
#   an exiting process.
#
# Test inputs:
#     "-u" get_user_pages_fast() benchmark
#     "-a" pin_user_pages_fast() benchmark
#     "-ct -F 0x1 0 19 0x1000" Dump pages 0, 19, and 4096, using pin_user_pages
#
# Expected Results:
#   For gup tests-
#     PASS: PIN_FAST_BENCHMARK: Time: get:<time> within threshold:<time> us.
#     PASS: PIN_FAST_BENCHMARK: Time: put:<time> within threshold:<time> us.
#     PASS: GUP_FAST_BENCHMARK: Time: get:<time> within threshold:<time> us.
#     PASS: GUP_FAST_BENCHMARK: Time: put:<time> within threshold:<time> us.
#     DUMP_USER_PAGES_TEST: done
#   For process_mrelease-
#     Success reaping a child with 1MB of memory allocations
#
# Results location:
#     output.txt

FILE=$(readlink -f "${BASH_SOURCE[0]}")
CDIR=$(dirname "$FILE")
. "$CDIR"/../../cki_lib/libcki.sh || exit 1

do_mm_run()
{
    pushd "${EXEC_DIR}" || exit
    total=$(grep -c "^mm:" kselftest-list.txt)
    tests="$(grep  "^mm:" kselftest-list.txt)"
    for test in ${tests}
    do
        num=$((num + 1))
        # report results as a subphase
        rlPhaseStartTest "selftests: ${test}"
        if [ "${test}" = "mm:run_vmtests.sh" ]; then
            if cki_is_kernel_automotive ; then
                sed -i "s/mm:run_vmtests.sh/mm:run_mm_tests.sh/" kselftest-list.txt
                cat >> mm/run_mm_tests.sh << EOF
#!/bin/bash

exitcode=0
factor=20 #20%
# Baseline values
pin_get_baseline=\${pin_get_baseline}
pin_put_baseline=\${pin_put_baseline}
gup_get_baseline=\${gup_get_baseline}
gup_put_baseline=\${gup_put_baseline}

# Setting the thresholds
pin_get_threshold=\$((\$((pin_get_baseline * factor / 100)) + pin_get_baseline))
pin_put_threshold=\$((\$((pin_put_baseline * factor / 100)) + pin_put_baseline))
gup_get_threshold=\$((\$((gup_get_baseline * factor / 100)) + gup_get_baseline))
gup_put_threshold=\$((\$((gup_put_baseline * factor / 100)) + gup_put_baseline))

echo "=== Running gup_test -a ==="
gup_test_pin_fast_benchmark(){
    # Collect pin benchmark
    pin_fast_benchmark=\$(./gup_test -a)
    if [[ "\$pin_fast_benchmark" == "check if CONFIG_GUP_TEST is enabled in kernel config" ]]; then
        echo "\$pin_fast_benchmark"
    else
        # Capture and compare the get and put times from pin fast benchmark
        pin_get_microsecs=\$(echo \$pin_fast_benchmark | awk -F ":" '{print \$4}' | awk '{print \$1}')
        pin_put_microsecs=\$(echo \$pin_fast_benchmark | awk -F ":" '{print \$5}' | awk '{print \$1}')
        if [[ \$pin_get_microsecs -gt \$pin_get_threshold ]]; then
            echo "FAIL: PIN_FAST_BENCHMARK: Time: get:\$pin_get_microsecs exceeds threshold:\$pin_get_threshold us."
            exitcode=1
        else
            echo "PASS: PIN_FAST_BENCHMARK: Time: get:\$pin_get_microsecs within threshold:\$pin_get_threshold us."
        fi
        if [[ \$pin_put_microsecs -gt \$pin_put_threshold ]]; then
            echo "FAIL: PIN_FAST_BENCHMARK: Time: put:\$pin_put_microsecs exceeds threshold:\$pin_put_threshold us."
            exitcode=1
        else
            echo "PASS: PIN_FAST_BENCHMARK: Time: put:\$pin_put_microsecs within threshold:\$pin_put_threshold us."
        fi
    fi
}

if [[ -n \${pin_get_baseline} ]] && [[ -n \${pin_put_baseline} ]]; then
    gup_test_pin_fast_benchmark
else
    echo "SKIP: pin fast benchmarks, no baselines set."
fi

echo "=== Running gup_test -u ==="
gup_test_gup_fast_benchmark(){
    # Collect gup benchmark
    gup_fast_benchmark=\$(./gup_test -u)
    if [[ "\$gup_fast_benchmark" == "check if CONFIG_GUP_TEST is enabled in kernel config" ]]; then
        echo "\$gup_fast_benchmark"
    else
        # Capture and compare the get and put times from gup fast benchmark
        gup_get_microsecs=\$(echo \$gup_fast_benchmark | awk -F ":" '{print \$4}' | awk '{print \$1}')
        gup_put_microsecs=\$(echo \$gup_fast_benchmark | awk -F ":" '{print \$5}' | awk '{print \$1}')
        if [[ \$gup_get_microsecs -gt \$gup_get_threshold ]]; then
            echo "FAIL: GUP_FAST_BENCHMARK: Time: get:\$gup_get_microsecs exceeds threshold:\$gup_get_threshold us."
            exitcode=1
        else
            echo "PASS: GUP_FAST_BENCHMARK: Time: get:\$gup_get_microsecs within threshold:\$gup_get_threshold us."
        fi
        if [[ \$gup_put_microsecs -gt \$gup_put_threshold ]]; then
            echo "FAIL: GUP_FAST_BENCHMARK: Time: put:\$gup_put_microsecs exceeds threshold:\$gup_put_threshold us."
            exitcode=1
        else
            echo "PASS: GUP_FAST_BENCHMARK: Time: put:\$gup_put_microsecs within threshold:\$gup_put_threshold us."
        fi
    fi
}

if [[ -n \${gup_get_baseline} ]] && [[ -n \${gup_put_baseline} ]]; then
    gup_test_gup_fast_benchmark
else
    echo "SKIP: gup fast benchmarks, no baselines set."
fi

echo "=== Running gup_test -ct -F 0x1 0 19 0x1000 ==="
./gup_test -ct -F 0x1 0 19 0x1000
echo "=== Running mrelease_test ==="
./mrelease_test

exit \$exitcode
EOF
                chmod 755 mm/run_mm_tests.sh
                test="mm:run_mm_tests.sh"
                RunKSelfTest "${test}"
            else
                RunKSelfTest "${test}"
            fi
        else
            RunKSelfTest "${test}"
        fi
        ret=$?
        check_result "${num}" "${total}" "${test}" "$ret"
        rlPhaseEnd
    done
}
