#!/bin/bash

LOOKASIDE=https://github.com/yizhanglinux/blktests.git

rm -rf blktests
git clone $LOOKASIDE
pushd blktests

if ! modprobe -qn rdma_rxe; then
	export USE_SIW="1"
	sed -i "/rdma_rxe/d" ./tests/srp/rc
	sed -i "/rdma_rxe/d" ./tests/nvmeof-mp/rc
fi

# modprobe siw on ppc64le with distro less than RHEL8.4 will lead panic, BZ1919502
# siw srp testing with distro less than RHEL8.4 on x86_64 has issues
ARCH=$(uname -i)
ver="4.18.0-305"
KVER=$(uname -r)
if [[ "$ver" == "$(echo -e "$ver\n$KVER" | sort -V | tail -1)" ]]; then
	export USE_SIW="0"
fi

make
if (( $? != 0 )); then
	cki_abort_task "Abort test because build env setup failed"
fi

popd
