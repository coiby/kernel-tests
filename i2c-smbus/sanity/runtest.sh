#!/bin/bash -x
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/i2c-smbus/sanity
#   Description: Confirm i2c modules load and buses/devices can be detected
#   Author: Evan McNabb <emcnabb@redhat.com>
#   Author: William Gomeringer <wgomerin@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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

# For an i2c bus, are any devices attached/detected?
function detect_devices {
        bus=$1
        # First trim out header column/row
        output=`i2cdetect -y $bus | grep ':' |cut -f2- -d" "`
        # Next search for any device address numbers in the remaining output
        echo $output |egrep -q [[:digit:]]
        # Return code of grep is whether a device address was found or not
        return $?
} 


function setup {
	yum install -y i2c-tools
	if ! `which i2cdetect &>/dev/null`; then
		echo "i2cdetect (from i2c-tools RPM) not installed, exiting!"
		rstrnt-report-result $TEST/setup FAIL
		exit 1
	fi

	echo ""
	echo "*** verify i2c-dev module loads automatically"
	# The i2c-dev module is now loaded automatically when i2cdetect 
        # is executed. (BZ 1071397). Verify the command succeeds.
	if ! i2cdetect -y 0 ; then
		echo "i2cdetect command failed"
                rstrnt-report-result $TEST/setup FAIL
                exit 1
	else
                echo "i2cdetect command succeeded"

	fi

	# Verify i2c-dev module is now loaded
	if ! lsmod | grep i2c_dev ; then
                echo "i2c-dev module did not load automatically"
                rstrnt-report-result $TEST/setup FAIL
                exit 1
        else
                echo "i2c-dev module loaded automatically"

        fi

	echo ""
	echo "*** verify i2c-dev.conf modprobe.d file is present"
	# Verify i2c-dev.conf modprobe.d file exists (BZ 1195285)
        if ! ls /usr/lib/modprobe.d/i2c-dev.conf ; then
                echo "i2c-dev.conf modprobe.d file is missing"
                rstrnt-report-result $TEST/setup FAIL
                exit 1
        else
                echo "i2c-dev.conf modprobe.d file is present"

        fi


	if ! `which i2cdetect &>/dev/null`; then
                echo "i2cdetect (from i2c-tools RPM) not installed, exiting!"
                rstrnt-report-result $TEST/setup FAIL
                exit 1
        fi

	rstrnt-report-result $TEST/setup PASS
}


function print_info {
	echo "--------------------- Debug Information ---------------------"
	echo "*** lspci:"
	lspci | grep -i smbus
	echo ""

	echo "*** sysfs:"
	ls -l /sys/bus/i2c/devices/
	echo ""

	echo "*** lsmod:"
	lsmod |grep i2c
	echo ""

	echo "*** i2cdetect -l:"
	i2cdetect -l
	echo ""

	echo "*** dmesg output:"
	dmesg | grep -i smbus
	echo ""

	rstrnt-report-result $TEST/info PASS
}

function test_buses {
	echo "--------------------- Detecting Buses/Devices ---------------"

	# How many total i2c devices have we detected so far?
	DEVCOUNT=0

	# Pull out list of bus numbers: 1, 2, 3, ...
	BUSLIST=`i2cdetect -l | cut -f1 | cut -f2 -d"-"`

	for bus in $BUSLIST; do
		echo "========== Bus i2c-$bus ========== "
		i2cdetect -F $bus
		echo "-> Scan bus output:"
		i2cdetect -y $bus
		echo "-> Were i2c devices detected? (non '--' field in output above)"
		if `detect_devices $bus`; then
			echo "*** Yes"
			let DEVCOUNT++
		else
			echo "*** No"
		fi
	done
	echo -e "===============================\n"

	echo "A total of \"$DEVCOUNT\" i2c devices were detected across all buses."
	if [ "$DEVCOUNT" -eq 0 ]; then
		echo "Test FAIL: No devices were found. This could be due to i2c not initializing correctly or there are not actually any i2c devices on the system (usually not the case). This should be investigated further."
		rstrnt-report-result $TEST/test_buses FAIL
	else
		echo "Test PASS: Devices were detected."
		rstrnt-report-result $TEST/test_buses PASS
	fi
}

setup
print_info
test_buses

