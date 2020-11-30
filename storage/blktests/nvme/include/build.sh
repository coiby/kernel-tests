#!/bin/bash

LOOKASIDE=https://github.com/yizhanglinux/blktests.git

rm -rf blktests
git clone $LOOKASIDE
cd blktests
make
exit $?
