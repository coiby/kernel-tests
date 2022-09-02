#!/bin/bash

LOOKASIDE=https://github.com/yizhanglinux/blktests.git
rlIsRHEL 7 && BR=rhel7 || BR=nvme-rdma-tcp
rm -rf blktests
git clone -b $BR $LOOKASIDE
pushd blktests
make
if (( $? != 0 )); then
    cki_abort_task "Abort test because build env setup failed"
fi

popd
