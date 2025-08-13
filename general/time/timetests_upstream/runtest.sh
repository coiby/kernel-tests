#!/bin/bash
#
# Author: Qiao Zhao <qzhao@redhat.com>  August 15, 2015
#

: "${TEST:=general/time/timetests_upstream}"

clone_upstream_code()
{
    if [ ! -d timetests ]; then
        git config --global http.sslVerify false
        git clone https://gitlab.com/redhat/centos-stream/tests/kernel/core/timetests.git --depth=1
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
        for pkg in "$@"; do
            if stat /run/ostree-booted > /dev/null 2>&1; then
                rpm -q "$pkg" || rpm-ostree -A --idempotent --allow-inactive install "$pkg" || echo "Install pakcage $pkg failed!"
            else
                rpm -q "$pkg" || yum install -y "$pkg" || echo "Install pakcage $pkg failed!"
            fi
        done
    fi
}

check_release_version()
{
    kernbase=$(rpm -q --queryformat '%{name}-%{version}-%{release}.%{arch}\n' -qf /boot/config-$(uname -r))
    echo $kernbase
}

ntp_chrony_service_handling()
{
    systemctl "$@" ntpd || service ntpd "$@" || true
    systemctl "$@" chronyd || service chronyd "$@" || true
}

runtest()
{
    check_release_version
    install_depends_package git make gcc psmisc
    clone_upstream_code
    ntp_chrony_service_handling stop

    pushd timetests
    sed -i '1i\set -x' runall.sh
    chmod a+x runall.sh
    ./runall.sh | tee -a /tmp/timetests.log
    sleep 60
    rstrnt-report-log -l /tmp/timetests.log
    popd

    ntp_chrony_service_handling start

    if [[ $(grep "FAILED" /tmp/timetests.log) ]]; then
        rstrnt-report-result "$TEST" "FAIL" 1
    else
        rstrnt-report-result "$TEST" "PASS" 0
    fi
}

###  Start here  ###
runtest
exit 0
