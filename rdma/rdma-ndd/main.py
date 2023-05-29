#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""rdma-ndd functional test"""

__author__ = "Zhaojuan Guo"
__copyright__ = "Copyright (c) 2023 Red Hat, Inc. All rights reserved."

from rdmaqe.common.tc import Test

import libsan.host.linux as linux
from libsan.host.cmdline import run
from stqe.host.atomic_run import atomic_run

from setup import change_nd_format

import sys


def test(tc):
    print("\n#######################################\n")
    print("INFO: Testing rdma-ndd.")

    # pre-test
    # test
    # case 1, service operation
    errors_service = []
    arguments_service = [
        {
            "message": "Service operation.",
            "service_name": "rdma-ndd",
            "command": linux.service_stop,
        },
        {
            "message": "Service operation.",
            "service_name": "rdma-ndd",
            "command": linux.service_start,
        },
        {
            "message": "Service operation.",
            "service_name": "rdma-ndd",
            "command": linux.service_status,
        },
        {
            "message": "Service operation.",
            "service_name": "rdma-ndd",
            "command": linux.is_service_running,
        },
    ]

    for argument in arguments_service:
        atomic_run(errors=errors_service, **argument) 

    if len(errors_service) == 0:         
        tc.tpass("Service operation passed.")     
    else:         
        tc.tfail("Service operation failed with following errors: \n\t'" + "\n\t ".join([str(i) for i in errors_service]))

    # case 2, change the node description format for all the RDMA devices
    _, nd_before = run('cat /sys/class/infiniband/*/node_desc | grep $(hostname -s) | wc -l', return_output=True)
    change_nd_format("%%h")
    new_hostname = "mynewhostname"
    _cmd = 'hostname ' + new_hostname
    run(_cmd)
    run('cat /sys/class/infiniband/*/node_desc', return_output=True, verbose=True)
    _, nd_after = run('cat /sys/class/infiniband/*/node_desc | grep $(hostname -s) | wc -l', return_output=True)

    if nd_before == nd_after:
        tc.tpass("Changing node_desc format passed")
    else:
        tc.tfail("Changing node_desc format failed")

    # post-test
    # Change the node_desc format to the default one
    print("Changing the node_desc format to the default one.")
    change_nd_format("%h %d")

    return 0


def main():
    test_class = Test()

    ret = test(test_class)
    print("Test return code: %s" % ret)

    if not test_class.tend():
        print("FAIL: test failed")
        sys.exit(1)

    print("PASS: rdma-ndd functional test passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
