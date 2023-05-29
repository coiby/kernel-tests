#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""rdma tool in iproute functional test"""

__author__ = "Zhaojuan Guo"
__copyright__ = "Copyright (c) 2023 Red Hat, Inc. All rights reserved."

from rdmaqe.rdma.general import is_rdma_device
from rdmaqe.common.tc import Test

import libsan.host.linux as linux

from stqe.host.atomic_run import atomic_run

import sys


def test(tc):
    print("\n#######################################\n")
    print("INFO: Testing rdma tool in iproute.")

    # pre-test
    # Skip if no RDMA device found on the testing machine
    if not is_rdma_device():
        tc.tskip("No RDMA device found on this testing machine.")
        return 2
    # test
    errors_pkg = []
    arguments_pkg = [
        {
            "message": "Package operation.",
            "pack": "iproute",
            "command": linux.install_package,
        },
    ]
    for argument in arguments_pkg:
        atomic_run(errors=errors_pkg, **argument) 
    if len(errors_pkg) == 0:
        tc.tpass("Package operation passed.")
    else:
        tc.tfail("Package operation failed with following errors: \n\t'" + "\n\t ".join([str(i) for i in errors_pkg]))

    test_cases = [
        "rdma --help",
        "rdma -V",
        "rdma --version",
        "rdma dev help",
        "rdma dev",
        "rdma dev show -d",
        "rdma system help",
        "rdma system show -d",
        "rdma sys set netns exclusive",
        "ip netns add foo",
        "ip netns delete foo",
        "rdma link help",
        "rdma link show -dpj",
        "rdma dev show -dpj",
        "rdma resource help",
        "rdma res show cm_id",
        "rdma res show cq",
        "rdma res show mr",
        "rdma statistic help",
        "rdma statistic show -d",
        "rdma statistic qp show",
        "rdma statistic qp mode",
    ]
    for _t in test_cases:
        t = "timeout --preserve-status 5 " + _t
        tc.tok(t)

    # post-test


def main():
    test_class = Test()
    test(test_class)
    # print("Test return code: %s" % ret)
    if not test_class.tend():
        print("FAIL: test failed")
        sys.exit(1)
    # if ret == 2:
        # print("SKIP: test has been skipped because no RDMA device found on the testing machines.")
        # sys.exit(2)
    print("PASS: rdma tool in iproute functional tests passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
