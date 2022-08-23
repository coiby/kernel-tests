#!/bin/bash

LOOKASIDE=https://github.com/osandov/blktests.git

rm -rf blktests
git clone $LOOKASIDE
pushd  blktests
make
if (( $? != 0 )); then
    cki_abort_task "Abort test because build env setup failed"
fi

popd
