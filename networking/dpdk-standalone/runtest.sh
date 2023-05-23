#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   runtest.sh of /kernel/networking/dpdk-standalone
#   Author: Hekai Wang <hewang@redhat.com>
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# variables
init_all_env()
{
    set -a
    PACKAGE="kernel"
    CASE_PATH=${CASE_PATH:-"/mnt/tests/kernel/networking/dpdk-standalone"}
    source /etc/os-release
    SYSTEM_VERSION_ID=$(echo $VERSION_ID | tr -d '.')
    set +a

    update_buildroot_repo

    source /mnt/tests/kernel/networking/common/include.sh || exit 1
    source /mnt/tests/kernel/networking/common/lib/lib_nc_sync.sh || exit 1
    source /mnt/tests/kernel/networking/common/lib/lib_netperf_all.sh || exit 1
    source ${CASE_PATH}/env.sh || exit 1

    set -a
    ZMQ_PORT=5678
    MAIN_FILE="main.py"
    set +a

    set -a
    release_full=$(cat /etc/redhat-release)
    if [[ $release_full =~ 7.9 ]]
    then
        X_VERSION=7
    elif [[ $release_full =~ 8. ]]
    then
        X_VERSION=8
    elif [[ $release_full =~ 9. ]]
    then
        X_VERSION=9
    else
        echo "You're not running this on rhel7.9 or rhel8.x or rhel9.x, so may not support yet."
        exit 1
    fi
    set +a
}

#first compile dpdk
#install dpdk to /usr/lcoal/dpdk
#enalbe l2fwd,l3fwd app default
#compile dpdk
#app dir /root/dpdk-20.08/build/app
#usertools dir /root/dpdk-20.08/usertools
#examples dir /root/dpdk-20.08/build/examples
#export PKG_CONFIG_PATH=/usr/local/dpdk/lib64/pkgconfig/:${PKG_CONFIG_PATH}
#pkg info only for install of dpdk
compile_and_install_dpdk()
{
    local install_dir=/usr/local/dpdk/
    pushd ${CASE_PATH}
    if [[ $DPDK_TEST_OPTION == "source" ]]
    then
        #install python and python-pip
        yum -y install python3 python2
        yum -y install python3-pip python2-pip
        pip3 install pyelftools
        #install numa-devel for numa support
        rpm -q numactl-devel || yum -y install numactl-devel
        #install for mlx4 and mlx5 support
        rpm -q rdma-core-devel || yum -y install rdma-core-devel
        rpm -q meson || yum -y install meson
        rpm -q ninja-build || yum -y install ninja-build
        local dpdk_source=${DPDK_SOURCE}
        local file_name=`basename ${dpdk_source}`
        [[ -f ${file_name} ]] && {
            # local dir_name=`find ./ -type d -name "dpdk-*"`
            local dir_name=`tar -tf $file_name | head -n 1 | tr -d '/'`
            [[ -d ${dir_name} ]] && {
                local dpdk_testpmd=${CASE_PATH}/${dir_name}/build/app/dpdk-testpmd
                local dpdk_l3fwd=${CASE_PATH}/${dir_name}/build/examples/dpdk-l3fwd
                local dpdk_devbind=${CASE_PATH}/${dir_name}/usertools/dpdk-devbind.py
                [[ -f ${dpdk_testpmd} ]] && [[ -f ${dpdk_l3fwd} ]] && [[ -f ${dpdk_devbind} ]] && {
                    set -x
                    export COMPILE_DPDK_TESTPMD=${CASE_PATH}/${dir_name}/build/app/dpdk-testpmd
                    export COMPILE_DPDK_L3_FWD=${CASE_PATH}/${dir_name}/build/examples/dpdk-l3fwd
                    export COMPILE_DPDK_DEV_BIND=${CASE_PATH}/${dir_name}/usertools/dpdk-devbind.py
                    export DPDK_ROOT_DIR=${CASE_PATH}/${dir_name}
                    export DPDK_DIR_NAME=${dir_name}
                    set +x
                    return 0
                }
            }
        }
        wget ${dpdk_source} > /dev/null 2>&1
        tar -xvf ${file_name}
        sleep 10
        # local dir_name=`find ./ -type d -name "dpdk-*"`
        local dir_name=`tar -tf $file_name | head -n 1 | tr -d '/'`
        pushd ${dir_name}
        meson build
        pushd build
        meson configure -Dexamples=l2fwd,l3fwd
        meson configure -Dprefix=/usr/local/dpdk/
        ninja
        popd
        popd
        set -x
        export COMPILE_DPDK_TESTPMD=${CASE_PATH}/${dir_name}/build/app/dpdk-testpmd
        export COMPILE_DPDK_L3_FWD=${CASE_PATH}/${dir_name}/build/examples/dpdk-l3fwd
        export COMPILE_DPDK_DEV_BIND=${CASE_PATH}/${dir_name}/usertools/dpdk-devbind.py
        export DPDK_ROOT_DIR=${CASE_PATH}/${dir_name}
        export DPDK_DIR_NAME=${dir_name}
        set +x
    else
        echo "The Current dpdk mode is "${DPDK_TEST_OPTION}
    fi
    popd
}

#check beaker-buildroot repo
#if repo status is disabled
#disable this repo
update_buildroot_repo()
{
    local repo_status=$(yum repoinfo beaker-buildroot | grep Repo-status | awk '{print $NF}')
    if [[ $repo_status == "disabled" ]]
    then
        dnf config-manager --disable beaker-buildroot
    fi
}

tools_install()
{
    update_buildroot_repo
    yum install -yq git wget tar go qperf pciutils
    yum -y install podman
    touch /etc/containers/nodocker
    yum -y install docker
    if [[ $X_VERSION == 8 ]] || [[ $X_VERSION == 9 ]]
    then
        dnf -y install container-selinux
        dnf -y install golang
    fi
    #package install for docker and podman
    dnf -y install wget vim tcpdump
    dnf -y install podman docker
    touch /etc/containers/nodocker
}

#for basic python2 and python3 install
install_python()
{
    #add epel repo
    dnf -y install curl
    local url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm"
    local test_reuslt=$(curl -s --head ${url} | head -n 1 | awk '{print $NF}' | tr -d '\r')
    if [[ $test_reuslt == "OK" ]]; then
        rpm -q epel-release || yum -y install ${url}
    else
        yum install dnf-utils
        local cur_ver=$(rpm -E '%{rhel}')
        local older_ver=$(( cur_ver - 1))
        local arch_val=$(rpm -E '%{_arch}')
        yum-config-manager --add-repo https://dl.fedoraproject.org/pub/epel/${older_ver}/Everything/${arch_val}/
        yum-config-manager --add-repo https://dl.fedoraproject.org/pub/epel/${older_ver}/Modular/${arch_val}/
        rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-${older_ver}
    fi

    yum makecache
    yum -y install sshpass

    if (( $SYSTEM_VERSION_ID < 82 ))
    then
        yum -y install python2
        yum -y install python2-pip
        yum -y install python2-devel
        yum -y install python36
        yum -y install python36-pip
        yum -y install python36-devel
        yum -y install python36-setuptools
    elif (( $SYSTEM_VERSION_ID >= 82 )) && (( $SYSTEM_VERSION_ID < 84 ))
    then
        yum -y install python38
        yum -y install python38-pip
        yum -y install python38-devel
        yum -y install python38-setuptools
    elif (( $SYSTEM_VERSION_ID >= 84 )) && (( $SYSTEM_VERSION_ID < 90 ))
    then
        yum -y install python39
        yum -y install python39-pip
        yum -y install python39-devel
        yum -y install python39-setuptools
    else
        #for rhel9 and newer distro version
        yum -y install python3.11
        yum -y install python3.11-pip
        yum -y install python3.11-devel
        yum -y install python3.11-setuptools
    fi

    if (($SYSTEM_VERSION_ID < 80)); then
        python2 -m pip install --upgrade pip==20.3.4
        python2 -m pip install wheel
        python2 -m pip install netifaces
        python2 -m pip install six
    fi
}

install_python_and_init_env()
{
    install_python
    pushd $CASE_PATH
    rpm -q libnl3-devel || yum -y install libnl3-devel
    rpm -q libvirt-devel || yum -y install libvirt-devel
    rpm -q telnet || yum -y install telnet
    rpm -q vim || yum -y install vim
    # python3 -m venv ${CASE_PATH}/venv
    if (( $SYSTEM_VERSION_ID < 82 ))
    then
        python3.6 -m venv ${CASE_PATH}/venv
    elif (( $SYSTEM_VERSION_ID >= 82 )) && (( $SYSTEM_VERSION_ID < 84 ))
    then
        python3.8 -m venv ${CASE_PATH}/venv
    elif (( $SYSTEM_VERSION_ID >= 84 )) && (( $SYSTEM_VERSION_ID < 90 ))
    then
        python3.9 -m venv ${CASE_PATH}/venv
    else
        python3.11 -m venv ${CASE_PATH}/venv
    fi
    source venv/bin/activate
    pip install --upgrade pip -i https://mirrors.aliyun.com/pypi/simple/
    pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/
    pip install --upgrade pip
    pip install wheel
    pip install fire
    pip install paramiko
    pip install argparse
    pip install plumbum
    pip install ethtool
    pip install shell
    pip install libvirt-python
    pip install envbash
    pip install bash
    pip install pexpect
    pip install serial
    pip install pyserial
    pip install napalm
    pip install scapy
    pip install zmq
    popd
}

load_ice_firmware()
{
    #for rhel9 ice firmware loading
    if (($SYSTEM_VERSION_ID >= 90)) && [[ "$NIC_DRIVER" =~ ice ]]; then
        rm -f /lib/firmware/intel/ice/ddp/ice.pkg.xz
        xz -d $(rpm -ql linux-firmware | grep -E ice-[0-9]+)
        ln -s $(ls /lib/firmware/intel/ice/ddp/ice-*) /lib/firmware/intel/ice/ddp/ice.pkg
        ls -lrt /lib/firmware/intel/ice/ddp/
    fi
}

trap handle_ctrl_c INT
handle_ctrl_c()
{
    local my_pid=$(ps -ef | grep python | grep ${MAIN_FILE} | awk '{print $2}')
    kill -n 9 $my_pid
    exit
}

clean_previous_runtest()
{
    local my_script_name=$(ps -p $$ | grep -v PID | awk '{print $NF}')
    echo "My scripts name is "${my_script_name}

    local my_pid=$$
    echo "my pid is "$my_pid

    local my_child_pid=$(pgrep -P $my_pid)
    echo "child pid "$my_child_pid

    local run_pid=$(pgrep ${my_script_name})
    echo "${my_script_name} pid list "${run_pid}

    local N=0
    while true
    do
        for i in $run_pid
        do
            if grep -q $i <<< "${my_child_pid[@]}";then
                continue
            elif [[ $i == $my_pid ]];then
                continue
            else
                echo "kill ${my_script_name} pid "$i
                kill -9 $i
                kill -9 $i
                kill -9 $i
            fi
        done
        sleep 1
        N=$((N + 1))
        if [[ $N -ge 3 ]];then
            break
        fi
    done
}

clean_previous_python_process()
{
    local N=0
    while true
    do
        local run_pid=$(pgrep python)
        for i in $run_pid
        do
            echo "kill python pid "$i
            kill -9 $i
            kill -9 $i
            kill -9 $i
        done
        sleep 1
        N=$((N + 1))
        if [[ $N -ge 3 ]];then
            break
        fi
    done
}

start_main_process()
{
    pushd $CASE_PATH
    echo "Begin Start python process"
    source venv/bin/activate
    python -u ${MAIN_FILE}
    deactivate
    popd
}

start_bash_cmd()
{
    all_cmd_file="/tmp/all_cmd_file"
    pushd ${CASE_PATH} > /dev/null
    source venv/bin/activate
    while true
    do
        cmd=`python ${CASE_PATH}/client.py`
        echo "$cmd" >> ${all_cmd_file}
        eval "${cmd}"
    done
    popd > /dev/null
    deactivate
}

print_all_parameters()
{
    echo "================================================"
    echo "kernel=$(uname -a)"
    echo "SYSTEM_VERSION=$SYSTEM_VERSION"
    echo "CLIENTS=$CLIENTS"
    echo "SERVERS=$SERVERS"
    echo "NIC_DRIVER=$NIC_DRIVER"
    echo "IMG_GUEST=$IMG_GUEST"
    echo "CONN_TYPE=$CONN_TYPE"
    echo "NETSCOUT_HOST=$NETSCOUT_HOST"
    echo "SERVER_PORT_ONE=$SERVER_PORT_ONE"
    echo "SERVER_PORT_TWO=$SERVER_PORT_TWO"
    echo "CLIENT_PORT_ONE=$CLIENT_PORT_ONE"
    echo "CLIENT_PORT_TWO=$CLIENT_PORT_TWO"
    echo "SERVER_NIC1_MAC=$SERVER_NIC1_MAC"
    echo "SERVER_NIC2_MAC=$SERVER_NIC2_MAC"
    echo "CLIENT_NIC1_MAC=$CLIENT_NIC1_MAC"
    echo "CLIENT_NIC2_MAC=$CLIENT_NIC2_MAC"
    echo "TEST_ITEM_LIST=$TEST_ITEM_LIST"
    echo "TREX_URL=$TREX_URL"
    echo "NAY=$NAY"
    echo "================================================"
}

start_run_test()
{
    print_all_parameters

    init_all_env

    tools_install

    clean_previous_runtest

    clean_previous_python_process

    compile_and_install_dpdk

    install_python_and_init_env

    #load_ice_firmware

    start_bash_cmd &

    start_main_process

}
start_run_test
