#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""opa-fm functional test"""

__author__ = "Zhaojuan Guo"
__copyright__ = "Copyright (c) 2023 Red Hat, Inc. All rights reserved."

from rdmaqe.rdma.general import is_opa_device
from rdmaqe.common.tc import Test
from rdmaqe.rdma.opa import opa_setup

import libsan.host.linux as linux

from stqe.host.atomic_run import atomic_run

import sys


def test(tc):
    print("\n#######################################\n")
    print("INFO: Testing opa-fm.")

    # pre-test
    # Skip if no OPA device found on the testing machine
    if not is_opa_device():
        tc.tskip("No OPA device found on this testing machine.")
        return 2
    # setup for OPA
    opa_setup()
    # test
    errors_pkg = []
    arguments_pkg = [
        {
            "message": "Package operation.",
            "pack": "opa-fm",
            "command": linux.install_package,
        },
    ]
    for argument in arguments_pkg:
        atomic_run(errors=errors_pkg, **argument) 
    if len(errors_pkg) == 0:
        tc.tpass("Package operation passed.")
    else:
        tc.tfail("Package operation failed with following errors: \n\t'" + "\n\t ".join([str(i) for i in errors_pkg]))

    errors_service = []
    arguments_service = [
        {
            "message": "Service operation.",
            "service_name": "opafm",
            "command": linux.service_stop,
        },
        {
            "message": "Service operation.",
            "service_name": "opafm",
            "command": linux.service_start,
        },
        {
            "message": "Service operation.",
            "service_name": "opafm",
            "command": linux.service_status,
        },
        {
            "message": "Service operation.",
            "service_name": "opafm",
            "command": linux.is_service_running,
        },
    ]

    for argument in arguments_service:
        atomic_run(errors=errors_service, **argument) 

    if len(errors_service) == 0:         
        tc.tpass("Service operation passed.")     
    else:         
        tc.tfail("Service operation failed with following errors: \n\t'" + "\n\t ".join([str(i) for i in errors_service]))
    tc.tok("/usr/sbin/opafmcmd smShowCounters")
    tc.tok("/usr/sbin/opafmcmdall smLogLevel 7")
    # post-test


def main():
    test_class = Test()

    ret = test(test_class)
    print("Test return code: %s" % ret)

    if not test_class.tend():
        print("FAIL: test failed")
        sys.exit(1)
    if ret == 2:
        print("SKIP: test has been skipped because no OPA device found on the testing machines.")
        sys.exit(2)

    print("PASS: opa-fm functional test passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
