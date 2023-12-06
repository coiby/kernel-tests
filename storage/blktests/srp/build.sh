#!/bin/bash

LOOKASIDE=https://github.com/yizhanglinux/blktests.git

if rlIsRHEL 7; then
	BR=rhel7
elif rlIsRHEL 8; then
	BR=nvme-rdma-tcp
elif rlIsRHEL 9 || rlIsFedora || rlIsCentOS 9; then
	BR=rhel9-fedora
fi

rm -rf blktests
git clone -b $BR $LOOKASIDE
if [ $? -ne 0 ]; then
	echo "Aborting test because access $LOOKASIDE failed"
	rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
	rstrnt-abort --server "$RSTRNT_RECIPE_URL"/tasks/"$RSTRNT_TASKID"/status
fi
pushd blktests || exit 200

if ! modprobe -qn rdma_rxe; then
	export USE_SW_RDMA="SIW"
fi

# modprobe siw on ppc64le with distro less than RHEL8.4 will lead panic, BZ1919502
# siw srp testing with distro less than RHEL8.4 on x86_64 has issues
ver="4.18.0-305"
KVER=$(uname -r)
if [[ "$ver" == "$(echo -e "$ver\n$KVER" | sort -V | tail -1)" ]]; then
	export USE_SW_RDMA="RXE"
fi

make
# shellcheck disable=SC2181
if (( $? != 0 )); then
	cki_abort_task "Abort test because build env setup failed"
fi

popd || exit 200
