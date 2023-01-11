#!/bin/bash -x

export TEST="rdma/pyverbs-tests"
# to record how many commands fail
export bad=0

# Include the common libraries
. ./../common/rdma-qa.sh || exit 1

function setup {
    if ! RQA_exist_RDMA_HCA; then
        rstrnt-report-result $TEST SKIP
        exit
    fi
    # install the required packages for the Pyverbs test suite
    local pyverbs_pkg_req="python3-pyverbs"
    rpm -q $pyverbs_pkg_req || RQA_pkg_install $pyverbs_pkg_req
}

function run_tests {
    hca_ids=$(RQA_get_hca_id)
    for hca_id in ${hca_ids}; do
        ${PYEXEC} /usr/share/doc/rdma-core/tests/run_tests.py -v --dev ${hca_id}
	bad=$((${bad}+1))
    done
    return $bad
}

# Start test
#####################################################################
result=FAIL
TEST=${TEST}/standalone
RQA_system_info_for_debug
setup
run_tests
if [[ $bad -eq 0 ]]; then
    result=PASS
fi
# Report the result and submit the test log
rstrnt-report-result $TEST $result $bad

echo ' ------ end of runtest.sh.'
exit 0
