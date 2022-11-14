#!/bin/bash

# Source the common test script helpers
. /usr/bin/rhts-environment.sh

# Function to record where we are in the test after a reboot.
REBOOT_STATUS=/var/tmp/rdrand.status; touch "$REBOOT_STATUS"  # Status file to record
reboot_status() {
	status=$1
	if grep -q $status "$REBOOT_STATUS" ; then
		# Return if we've already executed this function
		echo "completed"
	else
		# Otherwise record this function has been run
		echo $status >> $REBOOT_STATUS
		echo ""
	fi
}

chk_support() {
	if [ "`reboot_status chk_support`" = "completed" ]; then return; fi
	echo '========== Checking Hardware Support ============' | tee -a ${OUTPUTFILE}

	echo "/proc/cpuinfo output:" | tee -a ${OUTPUTFILE}
	grep '^flags' /proc/cpuinfo | uniq | tee -a ${OUTPUTFILE}
	if grep -q rdrand /proc/cpuinfo ; then
		echo "*** rdrand CPU flag dectected." | tee -a ${OUTPUTFILE}
		report_result $TEST/supported PASS
	else
		echo "*** rdrand CPU flag *NOT* dectected!" | tee -a ${OUTPUTFILE}
		echo "*** Unsupported system, exiting now!" | tee -a ${OUTPUTFILE}
		report_result $TEST/supported FAIL
		exit 1
	fi
}

cleanup() {
	if [ "`reboot_status cleanup`" = "completed" ]; then return; fi
	echo '========== Clean up =============================' | tee -a ${OUTPUTFILE}
	pushd grb-rng-module ; make clean ; popd
	rm -f /tmp/*-raw
	# Remove nordrand option if it's currently set
	if grep -q nordrand /proc/cmdline ; then
		echo "*** System is booted with nordrand. Removing from grub..." | tee -a ${OUTPUTFILE}
		default=`grubby --default-kernel`
		grubby --remove-args="nordrand" --update-kernel=$default
		echo "Grub kernel lines:" | tee -a ${OUTPUTFILE}
		if [ -f /boot/grub/grub.conf ]; then
			grep 'kernel' /boot/grub/grub.conf | grep -v '^#' | tee -a ${OUTPUTFILE}
		elif [ -f /boot/grub2/grub.cfg ]; then
			grep 'linux.*/vmlinuz' /boot/grub2/grub.cfg | grep -v '^#' | tee -a ${OUTPUTFILE}
		else
			echo "Could not find grub/grub.conf nor grub2/grub.cfg" | tee -a ${OUTPUTFILE}
		fi
		echo "***** System rebooting now!" | tee -a ${OUTPUTFILE}
		report_result $TEST/cleanup PASS
		rhts-reboot
	else
		# Otherwise we're done
		report_result $TEST/cleanup PASS
	fi
}

get_random_bytes_setup() {
	test=$1
	# If the cleanup function has already completed (for example on the
	# final cleanup reboot), there is no reason to run this again. Exit
	# out.
	if grep -q cleanup $REBOOT_STATUS; then return; fi

	echo "DEBUG: /proc/cmdline output:" | tee -a ${OUTPUTFILE}
	cat /proc/cmdline | tee -a ${OUTPUTFILE}
	echo "-------" | tee -a ${OUTPUTFILE}

	# Disable rdrand in grub if:
	# 1) "nordrand" was passed to function
	# 2) it isn't already disabled
	if [ "$test" == "nordrand" ] && ! grep -q nordrand /proc/cmdline ; then
		echo "Updating grub to add nordrand..." | tee -a ${OUTPUTFILE}
		default=`grubby --default-kernel`
		grubby --args="nordrand" --update-kernel=$default
		echo "Grub kernel lines:" | tee -a ${OUTPUTFILE}
		if [ -f /boot/grub/grub.conf ]; then
			grep 'kernel' /boot/grub/grub.conf | grep -v '^#' | tee -a ${OUTPUTFILE}
		elif [ -f /boot/grub2/grub.cfg ]; then
			grep 'linux.*/vmlinuz' /boot/grub2/grub.cfg | grep -v '^#' | tee -a ${OUTPUTFILE}
		else
			echo "Could not find grub/grub.conf nor grub2/grub.cfg" | tee -a ${OUTPUTFILE}
		fi
		echo "***** System rebooting now!" | tee -a ${OUTPUTFILE}
		rhts-reboot
	fi

	# A bit of a hack: this reboot check should happen at the top of the function,
	# but we'll run after the above grub update (since disabling rdrand requires grub
	# to be modified and then the function must be run again on reboot.)
	if [ "`reboot_status get_random_bytes_setup-$test`" = "completed" ]; then return; fi

	echo "========== $test: Setup =========================" | tee -a ${OUTPUTFILE}
	pushd grb-rng-module
	if [ ! -f grb-rng.ko ]; then
		echo "Compiling test module:" | tee -a ${OUTPUTFILE}
		make | tee -a ${OUTPUTFILE}
	fi
	insmod grb-rng.ko
	if [ -c /dev/hwrng ]; then
		echo "Device /dev/hwrng exists, setup passes." | tee -a ${OUTPUTFILE}
		report_result $TEST/get_random_bytes/setup-$test PASS
	else
		echo "*** No /dev/hwrng device! Module compile or loading failed?" | tee -a ${OUTPUTFILE}
		report_result $TEST/get_random_bytes/setup-$test FAIL
		exit 1
	fi
	popd
}

# Copy raw random data and record runtime. Save for later processing.
get_random_bytes_test() {
	test=$1
	if [ "`reboot_status get_random_bytes_test-$test`" = "completed" ]; then return; fi
	testlog=/tmp/$test-raw
	echo "========== $test: get_random_bytes test =========================" | tee -a ${OUTPUTFILE}

	# First double check the device file was created by module
	if [ ! -c /dev/hwrng ]; then
		echo "*** No /dev/hwrng device! Module compile or loading failed?" | tee -a ${OUTPUTFILE}
		report_result $TEST/get_random_bytes/test-$test FAIL
		exit 1
	fi

	# Now copy data and verify it occurred
	echo "Copying data..." | tee -a ${OUTPUTFILE}
	dd </dev/hwrng bs=4096 count=100>/dev/null 2>$testlog
	echo "dd results:" | tee -a ${OUTPUTFILE}
	cat $testlog | tee -a ${OUTPUTFILE}
	rhts-submit-log -l $testlog

	if grep -q 'MB/s' $testlog; then
		report_result $TEST/get_random_bytes/test-$test PASS
	else
		report_result $TEST/get_random_bytes/test-$test FAIL
	fi
}

get_random_bytes_compare() {
	if [ "`reboot_status compare`" = "completed" ]; then return; fi
	echo "========== Checking results =====================================" | tee -a ${OUTPUTFILE}
	rdrand_speed=`grep 'MB/s' /tmp/rdrand-raw | cut -f 8 -d" "`
	nordrand_speed=`grep 'MB/s' /tmp/nordrand-raw | cut -f 8 -d" "`
	echo "-> rdrand enabled speed = $rdrand_speed MB/s" | tee -a ${OUTPUTFILE}
	echo "-> nordrand enabled speed = $nordrand_speed MB/s" | tee -a ${OUTPUTFILE}

	ratio=`echo "$rdrand_speed / $nordrand_speed" | bc`
	echo "   = rdrand_speed / nordrand_speed = ${ratio}x (rounded)" | tee -a ${OUTPUTFILE}

	# Now to decide what is an acceptable speedup. rdrand should be
	# significantly faster, but there are no hard numbers - choose an
	# arbitrary ratio.
	MIN_SPEEDUP_RATIO=3 # x times faster
	echo "Minimum required speed up is ${MIN_SPEEDUP_RATIO}x faster" | tee -a ${OUTPUTFILE}

	if [ $ratio -gt $MIN_SPEEDUP_RATIO ]; then
		report_result $TEST/compare/result PASS
	else
		report_result $TEST/compare/result FAIL
	fi
}

# Confirm rdrand instruction is supported on this system.
chk_support

# Use test module to copy data using rdrand. Should be very fast.
get_random_bytes_setup rdrand
get_random_bytes_test rdrand

# Reboot with rdrand disabled. Should be much slower than if rdrand is enabled.
get_random_bytes_setup nordrand
get_random_bytes_test nordrand

# Compare results between rdrand and nordrand
get_random_bytes_compare

cleanup
rm -f "$REBOOT_STATUS"

exit 0
