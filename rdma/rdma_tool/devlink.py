#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""devlink tool in iproute functional test"""

__author__ = "Zhaojuan Guo"
__copyright__ = "Copyright (c) 2023 Red Hat, Inc. All rights reserved."


from rdmaqe.rdma.general import is_rdma_device
from rdmaqe.common.tc import Test

import libsan.host.linux as linux

from stqe.host.atomic_run import atomic_run

import sys


def test(tc):
    print("\n#######################################\n")
    print("INFO: Testing devlink tool in iproute.")

    # pre-test
    # Skip if no RDMA device found on the testing machine
    if not is_rdma_device():
        tc.tskip("No RDMA device found on this testing machine.")
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
        "devlink help",
        "devlink dev help",
        "devlink dev param",
    ]
    for _t in test_cases:
        t = "timeout --preserve-status 5 " + _t
        tc.tok(t)

    # post-test


def main():
    test_class = Test()
    test(test_class)
    if not test_class.tend():
        print("FAIL: test failed")
        sys.exit(1)
    print("PASS: devlink tool in iproute functional tests passed")
    sys.exit(0)


if __name__ == "__main__":
    main()

