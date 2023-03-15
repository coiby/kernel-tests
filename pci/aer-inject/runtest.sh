#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/pci/aer-inject
#   Description: PCI-E Advanced Error Reporting (AER) software injection testing
#   Author: William R. Gomeringer <wgomerin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2022 Red Hat, Inc. All rights reserved.
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

# Include rhts environment
. /usr/bin/rhts-environment.sh
. /usr/lib/beakerlib/beakerlib.sh

# List of correctable and uncorrectable errors. Taken from aer-inject/aer.h
CORRECTABLE="RCVR BAD_TLP BAD_DLLP REP_ROLL REP_TIMER"
UNCORRECTABLE="TRAIN DLP POISON_TLP FCP COMP_TIME COMP_ABORT UNX_COMP RX_OVER MALF_TLP ECRC UNSUP"
AER_INJECT=/sbin/aer-inject
export AERINJECTVERSION=0.1
TARGET=aer-inject-$AERINJECTVERSION


# --------------- Setup ---------------
echo "Loading aer-inject module..."
if ! `modprobe aer-inject`; then
    echo "Unable to load aer-inject module, exiting"
    report_result "$TEST/setup" "FAIL"
    exit 0
fi
# Double check that /dev/aer-inject now exists
if [ ! -c /dev/aer_inject ]; then
    echo "/dev/aer_inject does not exist, exiting"
    report_result "$TEST/setup" "FAIL"
    exit 0
fi

# Confirm aer-inject userspace tool is installed
(yum -y install ras-tools;true)
if [ ! -f $AER_INJECT ]; then
    # no tool installed,build it
        # In RHEL6.1, aer-inject is included in the ras-utils package, so no need to compile.
    echo "--------------- Start aer-inject tool build ---------------"
    tar -xvf $TARGET.tar.bz2
    make -C $TARGET
    cp $TARGET/aer-inject /usr/local/sbin/
    trap "rm -rf *~ $TARGET /usr/local/sbin/aer-inject" 0
    AER_INJECT=/usr/local/sbin/aer-inject
fi

# --------------- Print Debug Info ----------
echo "============== System information: begin  ============="
lspci -vv
echo "============== System information: end    ============="

# --------------- Start Test  ---------------
# Loop through each PCI device and run aer-inject on capable devices

# If no capable devices are found, the test should show WARN in RHTS on termination
cap_dev_count=0

pcidev_list=`lspci |cut -f1 -d" "`
for pcidev in $pcidev_list; do
    echo "-=-=-=-=-=-=-=-=-=-= Testing $pcidev =-=-=-=-=-=-=-=-=-=-=-=-" |tee /dev/kmsg
    echo " * Checking AER support on: `lspci -s $pcidev`"
    # Confirm device supports AER, otherwise skip
    if [ -n "`lspci -vv -s $pcidev |grep ' Correctable-'`" ]; then
        echo " * Warning: Device not AER capable! Skipping..."
        continue
    elif [ -n "`lspci -vv -s $pcidev |grep ' Correctable\+'`" ]; then
        echo " * Device is AER capable. Can run aer-inject..."
    cap_dev_count=$[$cap_dev_count+1]
    else
        echo " * Warning: Device AER capability bit not set in lspci! Skipping..."
        continue
    fi

    bus=`echo $pcidev| cut -f1 -d:`
    dev=`echo $pcidev| cut -f2 -d: |cut -f1 -d.`
    fn=`echo $pcidev| cut -f2 -d: |cut -f2 -d.`
    echo " * Testing device bus=$bus dev=$dev fn=$fn"

    echo "Testing correctable errors: $CORRECTABLE"
    for err in $CORRECTABLE; do
        echo "---> Injecting correctable $err:" |tee /dev/kmsg
        rhts-flush
        echo "AER BUS $bus DEV $dev FN $fn COR_STATUS $err" | aer-inject 2>&1 |tee /dev/kmsg
        sleep 1
    done

    echo "Testing uncorrectable errors: $UNCORRECTABLE"
    for err in $UNCORRECTABLE; do
        echo "---> Injecting uncorrectable $err:" |tee /dev/kmsg
        rhts-flush
        echo "AER BUS $bus DEV $dev FN $fn UNCOR_STATUS $err" | aer-inject 2>&1 |tee /dev/kmsg
        sleep 1
    done
done

echo "cap_dev_count = $cap_dev_count"
if [ "$cap_dev_count" -eq 0 ]; then
    echo "No PCI-E devices found that support AER. Setting WARN."
    report_result "$TEST" "WARN"
    exit 0
fi

report_result "$TEST" "PASS"

echo "*** End of runtest.sh ***"
