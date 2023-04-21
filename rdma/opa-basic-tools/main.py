#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""opa-basic-tools functional test"""

__author__ = "Zhaojuan Guo"
__copyright__ = "Copyright (c) 2023 Red Hat, Inc. All rights reserved."

from rdmaqe.rdma.general import is_opa_device
from rdmaqe.common.tc import Test
from rdmaqe.rdma.opa import opa_setup

import libsan.host.linux as linux
from libsan.host.cmdline import run
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

    # Remote PMA query.
    # First get a valid remote LID. The chain below will get the last listed LID in the fabric.
    # Why the last LID? Because assuming the SM is running on this node, this node will
    # be listed first. The one that is last should therefore be a remote LID.
    cmd = "opasaquery | grep 'Type: FI' | tail -1 | awk '{print $2}'"
    ret, remote_LID = run(cmd, return_output=True)
    if "Failed" in remote_LID:
        tc.tfail(remote_LID)
        tc.tok("timeout 1m /usr/sbin/opacapture -d 4 mycapture.tgz")
        tc.tok("timeout 1m /usr/sbin/opahfirev")
        tc.tok("timeout 1m /usr/sbin/opainfo")
        tc.tok("timeout 1m /usr/sbin/opapmaquery")
        tc.tok("timeout 1m /usr/sbin/opaportconfig")
        tc.tok("timeout 1m /usr/sbin/opaportinfo")
        tc.tok("timeout 1m /usr/sbin/opasmaquery")
    else:
        _cmd = "opapmaquery -l " + remote_LID + " -m 0"
        tc.tok(_cmd)
        tc.tok("opasaquery")
        tc.tok("timeout 1m /usr/sbin/opacapture -d 4 mycapture.tgz")
        tc.tok("timeout 1m /usr/sbin/opahfirev")
        tc.tok("timeout 1m /usr/sbin/opainfo")
        tc.tok("timeout 1m /usr/sbin/opapmaquery")
        tc.tok("timeout 1m /usr/sbin/opaportconfig")
        tc.tok("timeout 1m /usr/sbin/opaportinfo")
        tc.tok("timeout 1m /usr/sbin/opasmaquery")
        tc.tok("timeout 1m /usr/sbin/opafabricinfo")
        tc.tok("timeout 1m /usr/sbin/opagetvf")
        tc.tok("timeout 1m /usr/sbin/opagetvf_env")
        tc.tok("timeout 1m /usr/sbin/oparesolvehfiport")
        tc.tok("timeout 1m /usr/sbin/opasaquery")

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
