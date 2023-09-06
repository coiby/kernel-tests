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
	echo "Aborting test because access github.com failed"
	rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
	rstrnt-abort --server "$RSTRNT_RECIPE_URL"/tasks/"$RSTRNT_TASKID"/status
fi
pushd blktests || exit 200
make
# shellcheck disable=SC2181
if (( $? != 0 )); then
	cki_abort_task "Abort test because build env setup failed"
fi

popd || exit 200
