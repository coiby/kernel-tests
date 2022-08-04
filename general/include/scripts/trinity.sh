#!/bin/bash
git clone https://github.com/kernelslacker/trinity.git
pushd trinity
./configure
make -j $(nproc)
make install
popd

trinity -h
