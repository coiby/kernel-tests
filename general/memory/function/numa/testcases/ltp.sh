#!/bin/bash

if [ ! -f /opt/ltp/runltp ]; then
    git clone --depth 1 https://gitlab.com/redhat/centos-stream/tests/kernel/core/ltp.git
    pushd ltp
    git checkout 20220930
    make autotools &> /dev/null
    ./configure &> /dev/null
    make -j$(getconf _NPROCESSORS_ONLN) &> /dev/null
    make install &> /dev/null
    popd
fi

/opt/ltp/runltp -o numa.log -f numa
ret=$?
if [ $ret -ne 0 ]; then
    ret=$(grep TFAIL /opt/ltp/output/numa.log | grep -c -v 'less than expected')
fi
exit $ret
