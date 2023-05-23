#!/bin/bash

#compile dpdk
#app dir /root/dpdk-20.08/build/app
#usertools dir /root/dpdk-20.08/usertools
#examples dir /root/dpdk-20.08/build/examples
#export PKG_CONFIG_PATH=/usr/local/dpdk/lib64/pkgconfig/:${PKG_CONFIG_PATH}
#pkg info only for install of dpdk
compile_and_install_dpdk()
{
    local package_name=$1
    local dpdk_src_packge=/root/guest_dpdk_source/${package_name}
    local work_dir=/root/compile-dpdk
    #install gcc for compile
    rpm -q gcc || yum -y install gcc
    #install numa-devel for numa support
    rpm -q numactl-devel || yum -y install numactl-devel
    #install for mlx4 and mlx5 support
    rpm -q rdma-core-devel || yum -y install rdma-core-devel
    rpm -q meson || yum -y install meson
    rpm -q ninja-build || yum -y install ninja-build
    mkdir -p ${work_dir}

    pushd ${work_dir}
    cp ${dpdk_src_packge} ./
    tar -xvf ${package_name}
    local dir_name=`find ./ -type d -name "dpdk-*"`
    pushd ${dir_name}
    meson build
    pushd build
    meson configure -Dexamples=l2fwd,l3fwd
    meson configure -Dprefix=/usr/local/dpdk/
    ninja
    #pop for build
    popd
    #pop for ${dir_name}
    popd
    export COMPILE_DPDK_TESTPMD=${work_dir}/${dir_name}/build/app/dpdk-testpmd
    export COMPILE_DPDK_L3_FWD=${work_dir}/${dir_name}/build/examples/dpdk-l3fwd
    export COMPILE_DPDK_DEV_BIND=${work_dir}/${dir_name}/usertools/dpdk-devbind.py

    rm -f /root/all_guest_cmd
    touch /root/all_guest_cmd
    echo "COMPILE_DPDK_TESTPMD=${work_dir}/${dir_name}/build/app/dpdk-testpmd" >> /root/all_guest_cmd
    echo "COMPILE_DPDK_L3_FWD=${work_dir}/${dir_name}/build/examples/dpdk-l3fwd" >> /root/all_guest_cmd
    echo "COMPILE_DPDK_DEV_BIND=${work_dir}/${dir_name}/usertools/dpdk-devbind.py" >> /root/all_guest_cmd

    #popd for work_dir
    popd
}

set -x
compile_and_install_dpdk $1
set +x
