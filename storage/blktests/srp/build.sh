#!/bin/bash

LOOKASIDE=https://github.com/yizhanglinux/blktests.git

rm -rf blktests
git clone $LOOKASIDE
cd blktests

if uname -ri | grep -qE "^5.*eln|^5.*el9|^5.*fc"; then
	export USE_SIW="1"
	sed -i "/rdma_rxe/d" ./tests/srp/rc
	sed -i "/rdma_rxe/d" ./tests/nvmeof-mp/rc
fi

make
