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

# modprobe siw on ppc64le with distro less than RHEL8.4 will lead panic, BZ1919502
ARCH=$(uname -i)
ver="4.18.0-303"
KVER=$(uname -r)
if [[ $ARCH == "ppc64le" ]] && [[ "$ver" == "$(echo -e "$ver\n$KVER" | sort -V | tail -1)" ]]; then
	export USE_SIW="0"
fi

make
