#!/bin/bash
#
# Author: Qiao Zhao <qzhao@redhat.com>  August 15, 2015
#

clone_upstream_code()
{
    if [ ! -d timetests ]; then
        git config --global http.sslVerify false
        git clone https://github.com/linuxqiao/timetests.git
    fi
    if [ -d timetests ]; then
        echo "Clone successful."
    else
        echo "Clone failed"
        rstrnt-report-result $TEST FAIL 1
        exit 1
    fi
}

install_depends_package()
{
    echo "Installing rpm(s) $*"
    if [[ $# -gt 0 ]]; then
        for pkg in $*; do
            rpm -q "$pkg" || yum install -y "$pkg" || echo "Install pakcage $pkg failed!"
        done
    fi
}

check_release_version()
{
    kernbase=$(rpm -q --queryformat '%{name}-%{version}-%{release}.%{arch}\n' -qf /boot/config-$(uname -r))
    echo $kernbase
}

runtest()
{
    check_release_version
    install_depends_package git make gcc psmisc
    clone_upstream_code

    pushd timetests
    sed -i '1i\set -x' runall.sh
    chmod a+x runall.sh
    ./runall.sh | tee -a /tmp/timetests.log
    sleep 60
    rstrnt-report-log -l /tmp/timetests.log
    popd

    if [[ $(grep "FAILED" /tmp/timetests.log) ]]; then
        rstrnt-report-result $TEST "FAIL" 1
    else
        rstrnt-report-result $TEST "PASS" 0
    fi
}

###  Start here  ###
runtest
exit 0
