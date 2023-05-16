#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""eth-tools-basic functional test"""

__author__ = "Zhaojuan Guo"
__copyright__ = "Copyright (c) 2023 Red Hat, Inc. All rights reserved."

from rdmaqe.common.tc import Test

import libsan.host.linux as linux
from libsan.host.cmdline import run
from stqe.host.atomic_run import atomic_run

import sys


def test(tc):
    print("\n#######################################\n")
    print("INFO: Testing eth-tools-basic.")

    # pre-test
    # test
    # PKG operation
    errors_pkg = []
    arguments_pkg = [
        {
            "message": "Package operation.",
            "pack": "eth-tools-basic",
            "command": linux.install_package,
        },
    ]
    for argument in arguments_pkg:
        atomic_run(errors=errors_pkg, **argument)
    if len(errors_pkg) == 0:
        tc.tpass("Package operation passed.")
    else:
        tc.tfail("Package operation failed with following errors: \n\t'" + "\n\t ".join([str(i) for i in errors_pkg]))
    # functionalities tests
    tc.tok("ethcapture -d 3 $(date '+%Y-%m-%d-%T')")
    tc.tok("/usr/sbin/ethbw -i 5 -d 100")
    tc.tok("/usr/sbin/ethshmcleanup")

    return 0


def main():
    test_class = Test()
    ret = test(test_class)
    print("Test return code: %s" % ret)

    if not test_class.tend():
        print("FAIL: test failed")
        sys.exit(1)

    print("PASS: eth-tools-basic functional test passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
