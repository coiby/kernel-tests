#!/bin/bash
git clone --depth 1 https://gitlab.com/redhat/centos-stream/tests/kernel/core/trinity.git
pushd trinity
./configure
make -j $(nproc)
make install
popd

trinity -h
