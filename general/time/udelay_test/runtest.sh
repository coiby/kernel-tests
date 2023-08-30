#!/bin/bash

# udelay() test script
#
# Test is executed by writing and reading to /sys/kernel/debug/udelay_test
# and exercises a variety of delays to ensure that udelay() is delaying
# at least as long as requested (as compared to ktime).
#
# Copyright (C) 2014 Google, Inc.
#
# This software is licensed under the terms of the GNU General Public
# License version 2, as published by the Free Software Foundation, and
# may be copied, distributed, and modified under those terms.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

TEST="general/time/udelay_test"

UDELAY_PATH=/sys/kernel/debug/udelay_test

k_name=$(rpm --queryformat '%{name}\n' -qf /boot/config-$(uname -r)|sed -e 's/-core//')
if ! rpm -q --quiet ${k_name}-devel-$(uname -r); then
    if stat /run/ostree-booted > /dev/null 2>&1; then
        rpm-ostree -A --idempotent --allow-inactive install -y ${k_name}-devel-$(uname -r)
    else
        yum install -y ${k_name}-devel-$(uname -r) || dnf install -y ${k_name}-devel-$(uname -r)
    fi
fi

setup()
{
    /sbin/insmod udelay_test/udelay_test.ko
    tmp_file=`mktemp`
}

test_one()
{
    delay=$1
    echo $delay > $UDELAY_PATH
    tee -a $tmp_file < $UDELAY_PATH
}

cleanup()
{
    if [ -f $tmp_file ]; then
        rm $tmp_file
    fi
    /sbin/rmmod udelay_test
}

trap cleanup EXIT

true && {
    unset ARCH
    pushd udelay_test
    make
    [ $? != 0 ] && retcode=1
    popd
    export ARCH=$(uname -m)
}

[ ! -e udelay_test/udelay_test.ko ] && {
    echo "Build udelay_test module failed!"
    rstrnt-report-result $TEST "SKIP"
    exit 1
}
echo "Build udelay_test module finished!"

setup

# Delay for a variety of times.
# 1..200, 200..500 (by 10), 500..2000 (by 100)
for (( delay = 1; delay < 200; delay += 1 )); do
    test_one $delay
done
for (( delay = 200; delay < 500; delay += 10 )); do
    test_one $delay
done
for (( delay = 500; delay <= 2000; delay += 100 )); do
    test_one $delay
done

# Search for failures
count=`grep -c FAIL $tmp_file`
if [ $? -eq "0" ]; then
    echo "ERROR: $count delays failed to delay long enough"
    retcode=1
fi

echo "- Testing finished!"
rstrnt-report-log -l $tmp_file

if [ $retcode = 1 ]; then
    rstrnt-report-result $TEST "FAIL" 1
else
    rstrnt-report-result $TEST "PASS" 0
fi

exit 0
