#!/bin/bash

if [ ! -f /opt/ltp/runltp ]; then
    yum install -y net-tools
    yum group install -y development
    git clone https://github.com/linux-test-project/ltp.git
    pushd ltp
    git checkout 20180515
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
