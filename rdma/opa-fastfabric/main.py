#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""opa-fastfabric functional test"""

__author__ = "Zhaojuan Guo"
__copyright__ = "Copyright (c) 2023 Red Hat, Inc. All rights reserved."

from rdmaqe.rdma.general import is_opa_device
from rdmaqe.common.tc import Test
from rdmaqe.rdma.opa import opa_setup, is_port_active
from rdmaqe.common.file_libs import configure_file

import libsan.host.linux as linux

from stqe.host.atomic_run import atomic_run

import sys


def test(tc):
    print("\n#######################################\n")
    print("INFO: Testing opa-fastfabric.")

    # pre-test
    # Skip if no OPA device found on the testing machine
    if not is_opa_device():
        tc.tskip("No OPA device found on this testing machine.")
        return 2
    # setup for OPA
    opa_setup()
    # configure host file
    _hosts = None
    if _hosts is None:
        _hosts = linux.hostname()
        configure_file("/etc/opa/hosts", _hosts)
    # test
    errors_pkg = []
    arguments_pkg = [
        {
            "message": "Package operation.",
            "pack": "opa-fastfabric",
            "command": linux.install_package,
        },
    ]
    for argument in arguments_pkg:
        atomic_run(errors=errors_pkg, **argument) 
    if len(errors_pkg) == 0:
        tc.tpass("Package operation passed.")
    else:
        tc.tfail("Package operation failed with following errors: \n\t'" + "\n\t ".join([str(i) for i in errors_pkg]))

    # host file
    _hosts = None
    if _hosts is None:
        _hosts = linux.hostname()
        configure_file("/etc/opa/hosts", _hosts)

    if not is_port_active():
        # Although there's no active port, these tests still can be run
        tc.tok("timeout 1m /usr/sbin/opapingall")
        tc.tok("timeout 1m /usr/sbin/opafindgood")
        tc.tok("timeout 1m /usr/sbin/opaextractstat /etc/opa/opaff.xml")
        tc.tok("timeout 1m /usr/sbin/opaexpandfile allhosts")
        tc.tok("timeout 1m /usr/sbin/opacabletest")
        tc.tok("timeout 1m /usr/sbin/opashowmc")
        tc.tok("timeout 1m /usr/sbin/opaswdisableall")
        tc.tok("timeout 1m /usr/sbin/opaswenableall")
    else:
        tc.tok("timeout 1m /usr/sbin/opapingall")
        tc.tok("timeout 1m /usr/sbin/opafindgood")
        tc.tok("timeout 1m /usr/sbin/opaswdisableall")
        tc.tok("timeout 1m /usr/sbin/opaswenableall")
        tc.tok("timeout 1m /usr/sbin/opareport")
        tc.tok("timeout 1m /usr/sbin/opareports")
        tc.tok("timeout 1m /usr/sbin/opascpall /tmp/hello /tmp/hello")
        tc.tok("timeout 1m /usr/sbin/opashowallports")
        tc.tok("timeout 1m /usr/sbin/opashowmc")
        tc.tok("timeout 1m /usr/sbin/opaextractbadlinks")
        tc.tok("timeout 1m /usr/sbin/opaextractstat /etc/opa/opaff.xml")
        tc.tok("timeout 1m /usr/sbin/opaextractlids")
        tc.tok("timeout 1m /usr/sbin/opaextractlink")
        tc.tok("timeout 1m /usr/sbin/opaextractperf")
        tc.tok("timeout 1m /usr/sbin/opaextractsellinks")
        tc.tok("timeout 1m /usr/sbin/opaexpandfile allhosts")
        tc.tok("timeout 1m /usr/sbin/opacheckload")
        tc.tok("timeout 1m /usr/sbin/opacmdall 'uname -a'")
        tc.tok("timeout 1m /usr/sbin/opaswitchadmin -a run info")
        tc.tok("timeout 1m /usr/sbin/opacabletest")
        tc.tok("timeout 1m /usr/sbin/opafabricanalysis -b")
        tc.tok("timeout 1m /usr/sbin/opafabricanalysis")
        tc.tok("timeout 1m /usr/sbin/opaallanalysis -b")
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

    print("PASS: opa-fastfabric functional test passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
