#!/bin/bash

export TEST="rdma/pyverbs-tests"
# to record how many commands fail
export bad=0

# Include the common libraries
. ./../common/rdma-qa.sh || exit 1

function setup {
    # install RDMA related packages if there exists RDMA HCA
    pkg_list="rdma-core libibverbs libibverbs-utils libibverbs-devel librdmacm librdmacm-utils librdmacm-devel perftest infiniband-diags opensm mstflint opa-fm opa-basic-tools opa-ff opa-fastfabric opa-address-resolution"
    if RQA_exist_RDMA_HCA; then
        RQA_pkg_install ${pkg_list}
    else
        rstrnt-report-result $TEST SKIP
        exit
    fi
    # install the required packages for the Pyverbs test suite
    local pyverbs_pkg_req="python3-pyverbs"
    rpm -q $pyverbs_pkg_req || RQA_pkg_install $pyverbs_pkg_req

    cd /usr/share/doc/rdma-core/tests/
    chmod +x run_tests.py
}

function run_tests {
    hca_ids=$(RQA_get_hca_id)
    for hca_id in ${hca_ids}; do
        ./run_tests.py -v --dev $hca_id
        let bad++
    done
    return $bad
}

# Start test
#####################################################################
result=FAIL
TEST=${TEST}/standalone
setup
run_tests
if [[ $bad -eq 0 ]]; then
    result=PASS
fi
# Report the result and submit the test log
rstrnt-report-result $TEST $result $bad

echo ' ------ end of runtest.sh.'
exit 0
