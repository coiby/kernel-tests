#!/bin/bash

LOOKASIDE=https://github.com/osandov/blktests.git

rm -rf blktests
git clone $LOOKASIDE 
cd blktests
make
exit $?
