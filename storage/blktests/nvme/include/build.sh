#!/bin/bash

LOOKASIDE=https://github.com/yizhanglinux/blktests.git
uname -r | grep -q 3.10 && BR=rhel7 || BR=nvme-rdma-tcp
rm -rf blktests
git clone -b $BR $LOOKASIDE
cd blktests

if ! modprobe -qn rdma_rxe; then
	export USE_SIW="1"
	sed -i "/rdma_rxe/d" ./tests/srp/rc
	sed -i "/rdma_rxe/d" ./tests/nvmeof-mp/rc
	sed -i "/rdma_rxe/d" ./tests/nvme/rc
fi

make
