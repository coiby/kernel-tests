#!/bin/bash

LOOKASIDE=https://github.com/yizhanglinux/blktests.git

rm -rf blktests
git clone $LOOKASIDE
cd blktests

if ! modprobe -qn rdma_rxe; then
	export USE_SIW="1"
	sed -i "/rdma_rxe/d" ./tests/srp/rc
	sed -i "/rdma_rxe/d" ./tests/nvmeof-mp/rc
fi

make
