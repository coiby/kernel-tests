#!/bin/bash
#
# Automotive does no support hugtblfs and mm:run_vmtests.sh requires it. However not all the subtests do.
# In order to get to gup_test, I need to bypass the check and run the tests that do not require hugtblfs support.
# Test is regression of https://bugzilla.redhat.com/show_bug.cgi?id=2073217 for risk assesment https://issues.redhat.com/browse/VROOM-20044.
#
do_mm_run()
{
    pushd "${EXEC_DIR}" || exit
    total=$(grep -c "^mm:" kselftest-list.txt)
    tests="$(grep  "^mm:" kselftest-list.txt)"
    for test in ${tests}
    do
        num=$((num + 1))
        if [ "${test}" = "mm:run_vmtests.sh" ]; then
            echo ${test}
            sed -i "s/mm:run_vmtests.sh/mm:run_gup_tests.sh/" kselftest-list.txt
            cat >> mm/run_gup_tests.sh << EOF
./gup_test -u
./gup_test -a
./gup_test -ct -F 0x1 0 19 0x1000
EOF
            chmod 755 mm/run_gup_tests.sh
            test="mm:run_gup_tests.sh"
            RunKSelfTest "${test}"
        else
            RunKSelfTest "${test}"
        fi
        ret=$?
        check_result "${num}" "${total}" "${test}" "$ret"
    done
}
