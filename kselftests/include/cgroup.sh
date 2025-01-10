#!/bin/bash
#
# Need to double wait time for cgroup:test_cpuset_prs.sh
# https://issues.redhat.com/browse/AUTOBUG-378
#
do_cgroup_run()
{
    pushd "${EXEC_DIR}" || exit
    total=$(grep -c "^cgroup:" kselftest-list.txt)
    tests="$(grep  "^cgroup:" kselftest-list.txt)"
    for test in ${tests}
    do
        num=$((num + 1))
        # report results as a subphase
        rlPhaseStartTest "${num}..${total} selftests: ${test}"
        if [ "${test}" = "cgroup:test_cpuset_prs.sh" ]; then
            pushd cgroup || exit
            ./"${test##cgroup:}" -d 2
            popd || exit
        else
            RunKSelfTest "${test}"
        fi
        ret=$?
        check_result "${num}" "${total}" "${test}" "$ret"
        rlPhaseEnd
    done
}
