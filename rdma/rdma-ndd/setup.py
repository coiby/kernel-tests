#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""rdma-ndd setup"""

__author__ = "Zhaojuan Guo"
__copyright__ = "Copyright (c) 2023 Red Hat, Inc. All rights reserved."

from libsan.host.cmdline import run


def change_nd_format(nd_format):
    _cmd = "cat /usr/lib/systemd/system/rdma-ndd.service | grep 'Environment=RDMA_NDD_ND_FORMAT='"
    retcode = run(_cmd)
    if retcode != 0:
        _cmd = "echo '[Service]\nEnvironment=RDMA_NDD_ND_FORMAT={0}' >> /usr/lib/systemd/system/rdma-ndd.service".format(
            nd_format)
        run(_cmd)

    else:
        _cmd = "sed -i '/Environment=RDMA_NDD_ND_FORMAT=/c\Environment=RDMA_NDD_ND_FORMAT={0}' " \
               "/usr/lib/systemd/system/rdma-ndd.service".format(nd_format)
        run(_cmd)
    run('systemctl daemon-reload')
    run('systemctl restart rdma-ndd.service')
