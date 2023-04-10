#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""opa-basic-tools functional test"""

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
    print("INFO: Testing opa-basic-tools.")

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
            "pack": "opa-basic-tools",
            "command": linux.install_package,
        },
    ]
    for argument in arguments_pkg:
        atomic_run(errors=errors_pkg, **argument) 
    if len(errors_pkg) == 0:
        tc.tpass("Package operation passed.")
    else:
        tc.tfail("Package operation failed with following errors: \n\t'" + "\n\t ".join([str(i) for i in errors_pkg]))

    tc.tok("/usr/sbin/opacapture -d 4 opacapture")
    tc.tok("/usr/sbin/opafabricinfo")
    tc.tok("/usr/sbin/opagetvf")
    tc.tok("/usr/sbin/opagetvf_env")
    tc.tok("/usr/sbin/opahfirev")
    tc.tok("/usr/sbin/opainfo")
    tc.tok("/usr/sbin/opapmaquery")
    tc.tok("/usr/sbin/opaportconfig")
    tc.tok("/usr/sbin/opaportinfo")
    tc.tok("/usr/sbin/oparesolvehfiport")
    tc.tok("/usr/sbin/opasaquery")
    tc.tok("/usr/sbin/opasmaquery")

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

    print("PASS: opa-basic-tools functional test passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
