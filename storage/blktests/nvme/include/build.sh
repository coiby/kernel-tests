#!/bin/bash

LOOKASIDE=https://github.com/yizhanglinux/blktests.git
uname -r | grep -q 3.10 && BR=rhel7 || BR=nvme-rdma-tcp
rm -rf blktests
git clone -b $BR $LOOKASIDE
cd blktests
make
exit $?
