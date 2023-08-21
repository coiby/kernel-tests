#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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

# include beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1
. ../../cki_lib/libcki.sh || exit 1

TEST="misc/module-load"

# Test doesn't run without IPv6
if grep "ipv6.disable=1" /proc/cmdline ; then
	rlLog "Skip test as system doesn't have IPv6."
	rstrnt-report-result $TEST SKIP
	exit
fi

# Commands in this section are provided by test developer.
# ---------------------------------------------

# Assume the test will fail.
result=FAIL

# Helper functions
function result_fail() {
	export result=FAIL
	rstrnt-report-result $TEST $result 0
	exit 0
}

function result_pass () {
	export result=PASS
	rstrnt-report-result $TEST $result 0
	exit 0
}

function mlog()
{
	msg=$1
	shift

	f=$1
	while [ -n "$f" ]; do
		if [ -e "$f" ]; then
			eval "$msg" >> $f
		fi
		shift
		f=$1
	done
}

function workaround_BZ1371265()
{
	# Bug 1371265 - [RHEL-6.8] module-load task fails - ip_queue: failed to register queue handler
	# https://bugzilla.redhat.com/show_bug.cgi?id=1371265
	local bz_module="nfnetlink_queue"
	local loaded=$(lsmod | grep -c "$bz_module")

	if [ "$loaded" -gt "0" ]; then
		echo "" | tee -a $OUTPUTFILE
		echo "***** BZ1371265: performing workaround" | tee -a $OUTPUTFILE
		echo "***** BZ1371265: unloading $bz_module" | tee -a $OUTPUTFILE
		rmmod $bz_module
		if [ $? -eq 0 ]; then
			echo "***** BZ1371265: successfully unloaded $bz_module" | tee -a $OUTPUTFILE
		else
			echo "***** BZ1371265: NOT able to unlooad $bz_module" | tee -a $OUTPUTFILE
		fi
		echo "" | tee -a $OUTPUTFILE
	fi
}

# Find our arch and get the appropriate list of modules for testing.
arch=$(uname -m)

case "$arch" in
	i?86)
		# shellcheck disable=SC2144
		if [ -s modules.i?86 ] ; then
			MODLIST=modules.i?86
		else
			MODLIST=modules.default
		fi
		;;
	x86_64)
		if [ -s modules.x86_64 ] ; then
			MODLIST=modules.x86_64
		else
			MODLIST=modules.default
		fi
		if cki_is_kernel_automotive; then
		  MODLIST=modules.x86_64.rhivos
		fi
		;;
	ia64)
		if [ -s modules.ia64 ] ; then
			MODLIST=modules.ia64
		else
			MODLIST=modules.default
		fi
		;;
	ppc*)
		# shellcheck disable=SC2144
		if [ -s modules.ppc* ] ; then
			MODLIST=modules.ppc*
		else
			MODLIST=modules.default
		fi
		;;
	s390)
		if [ -s modules.s390 ] ; then
			MODLIST=modules.s390
		else
			MODLIST=modules.default
		fi
		;;
	s390x)
		if [ -s modules.s390x ] ; then
			MODLIST=modules.s390x
		else
			MODLIST=modules.default
		fi
		;;
	armv7l)
		if [ -s modules.armv7l ] ; then
			MODLIST=modules.armv7l
		else
			MODLIST=modules.default
		fi
		;;
	aarch64)
		if [ -s modules.aarch64 ] ; then
			MODLIST=modules.aarch64
		else
			MODLIST=modules.default
		fi
		if cki_is_kernel_automotive; then
		  MODLIST=modules.aarch64.rhivos
		fi
		;;
	*)
		echo "Inappropriate value for \$arch: $arch" >> $OUTPUTFILE
		result_fail
		;;
esac

cat /etc/redhat-release | tee -a $OUTPUTFILE

release=""
cat /etc/redhat-release | grep "^Fedora"
if [ $? -ne 0 ]; then
	release=$(cat /etc/redhat-release |sed 's/.*\(release [0-9]\).*/\1/')
else
	release=$(cat /etc/fedora-release | sed 's/.*release \([0-9]*\).*/f\1/')
fi

if [ -z "$release" ]; then
	release=$(uname -r | grep -o el[0-9])
	echo "Taking release from kernel version: $release" | tee -a $OUTPUTFILE
fi


case "$release" in
	"release 4")
		if [ -s modules.rhel4 ]; then
			MODLIST="$MODLIST modules.rhel4"
		fi
		;;
	"release 5")
		if [ -s modules.rhel5 ]; then
			MODLIST="$MODLIST modules.rhel5"
		fi
		;;
	"release 6"|"el6")
		if [ -s modules.rhel6 ]; then
			MODLIST="$MODLIST modules.rhel6"
		fi
		;;
	"release 7"|"el7")
		if [ -s modules.rhel7 ]; then
			MODLIST="$MODLIST modules.rhel7"
		fi
		;;
	"release 8"|"el8")
		if [ -s modules.rhel8 ]; then
			MODLIST="$MODLIST modules.rhel8"
		fi
		;;
	"release 9"|"el9")
		if [ -s modules.rhel9 ] && ! cki_is_kernel_automotive ; then
			MODLIST="$MODLIST modules.rhel9"
		fi
		if cki_is_kernel_automotive; then
		  MODLIST="$MODLIST modules.rhivos"
		fi
		;;

	*)
		if [ -s "modules.$release" ]; then
			MODLIST="$MODLIST modules.$release"
		else
			echo "Warning: Running on unknown release: ${release}, using modules list contained in ${MODLIST}!"
		fi
		;;
esac

if [ "$release" = "release 6" ] || [ "$release" = "el6" ]; then
	workaround_BZ1371265
fi

# wireguard: a new module in rhel9, but disable in FIPS mode
if [ "$release" = "release 9" ] || [ "$release" = "el9" ]; then
	fips_enabled=`cat /proc/sys/crypto/fips_enabled`
	if [ "$fips_enabled" = "1" ]; then
		sed -i "s/wireguard/# \0/" modules.rhel9
	fi
fi

# c9s automotive kernel has crc8 built-in for aarch64, not a module
if grep -q CONFIG_CRC8=y /boot/config-$(uname -r); then
	sed -i 's/crc8/# \0/' modules.rhel9
fi

# likewise for c9s and CRYPTO_USER and CRYPTO_SHA512_SSSE3
if grep -q CONFIG_CRYPTO_USER=y /boot/config-$(uname -r); then
	sed -i 's/crypto_user/# \0/' modules.rhel9
fi
if grep -q CONFIG_CRYPTO_SHA512_SSSE3=y /boot/config-$(uname -r); then
	sed -i 's/sha512-ssse3/# \0/' modules.rhel9
fi

# skip blocked modules
for x in $(grep -o -w 'module_blacklist=[^[:space:]]*' /proc/cmdline |
			awk -F= '{print $2}' | tr ',' ' ') \
			$(grep -h ^blacklist /etc/modprobe.d/* | awk '{print $2}')
do
	for y in modules.* ; do
		sed -i "s/$x/# \0/" $y
		# remove dependencies too
		for z in $(awk -F: "/$x\.[^/[:space:]]*/ {print \$1}" \
					/lib/modules/$(uname -r)/modules.dep) ; do
					sed -i "s/$(basename $z .ko.xz)/# \0/" $y
		done
	done
done

# run the test. For each module in the MODLIST file, try to load it, check
# that it is there, then unload it and check lsmod again. All modules should
# be loadable/unloadable for each arch without issue.

# How many times do we want to load/unload each module?
ITERATIONS=3

pass=0
fail=0
skip=0

# increase message verbosity
printk_default=`cat /proc/sys/kernel/printk`
echo 9 > /proc/sys/kernel/printk

echo "*** Start of test ***" | tee -a $OUTPUTFILE
echo "** Module list prior to testing. **" | tee -a $OUTPUTFILE
/sbin/lsmod >> $OUTPUTFILE 2>&1
RC=$?
if [ $RC -ne 0 ] ; then
	echo "*** There is a problem with lsmod, no need to continue further ***" | tee -a $OUTPUTFILE
	cki_abort_task "There is a problem with lsmod"
fi

echo "** Doing $ITERATIONS load/unload cycles of each module in the file $MODLIST **" | tee -a $OUTPUTFILE
kernel_mod_dir="/lib/modules/`uname -r`"
for (( i = 0; i < $ITERATIONS; i++)); do
	for module in $(sed 's/#.*$//' $MODLIST) ; do
		# there is no difference between _ and - in kernel module
		# names, so convert all "-" to "_". Do this so things like grep
		# work correctly later on.
		module=`echo $module | tr '-' '_'`

		# known issues for specific architectures
		if [ "$(uname -m)" = "aarch64" ]; then
			# sd_mod is builtin to the aarch64 kernel
			if [ "$module" = "sd_mod" ]; then
				continue
			fi
		fi

		# get a module alias
		mod_alias=`cat "$kernel_mod_dir/modules.alias" | grep "alias $module " | cut -f3 -d' '`
		# Is the module already loaded?
		if [ $(/sbin/lsmod | grep -c $module) -gt 0 ] || ( [ ! -z "$mod_alias" ] && [ $(/sbin/lsmod | grep -c "$mod_alias") -gt 0 ] ); then
			echo "$module SKIPPED: appears to already be loaded into the kernel." >> $OUTPUTFILE
			skip=$(expr $skip + 1)
			continue
		fi

		modinfo $module > /dev/null 2>&1
		RC=$?
		if [ $RC -ne 0 ] ; then
			echo "WARNING: $module not found" >> $OUTPUTFILE
			continue
		fi

		mlog "echo \"** Attempting to load $module... **\"" /dev/console "$OUTPUTFILE"
		modprobe_out=$(/sbin/modprobe $module 2>&1)
		RC=$?
		if [ $RC -ne 0 ] ; then
			echo "** Modprobe FAILED, exit: $RC **"  >> $OUTPUTFILE
			fail=$(expr $fail + 1)
		fi

		echo $modprobe_out | grep "Cannot allocate memory" > /dev/null
		RC=$?
		if [ $RC -eq 0 ]; then
			mlog "echo \"ps afxu\"" /dev/console "$OUTPUTFILE"
			mlog "ps afxu" /dev/console "$OUTPUTFILE"
			mlog "echo \"cat /proc/slabinfo\"" /dev/console "$OUTPUTFILE"
			mlog "cat /proc/slabinfo" /dev/console "$OUTPUTFILE"
			echo m > /proc/sysrq-trigger
		fi

		# sleep 5
		if [ -e "/sys/module/$module/initstate" ]; then
			for k in $(seq 1 3); do
				initstate=$(cat /sys/module/$module/initstate)
				if [ "$initstate" == "live" ]; then
					echo "** $module is live **" >> $OUTPUTFILE
					break
				fi
				sleep 1
			done
		fi

		if [ $(/sbin/lsmod | grep -c $module) -gt 0 ] || ( [ ! -z "$mod_alias" ] && [ $(/sbin/lsmod | grep -c "$mod_alias") -gt 0 ] ); then
			echo "** $module loaded sucessfully. **" >> $OUTPUTFILE
			pass=$(expr $pass + 1)
		else
			echo "** $module FAILED to load. **" >> $OUTPUTFILE
			fail=$(expr $fail + 1)
		fi

		# workaround for Bug 1247156 - NM/udev rules prevent unloading of some kernel modules
		if [ -e "/sys/module/$module" ]; then
			mod_time1=$(stat --format='%y' "/sys/module/$module")
		fi

		# sleep 5

		# Bug 970521 - fuse module sometimes fails to unload
		# fuse module load triggers mount of fusectl
		# before removing this module we have to umount all fusectl filesystems
		if [ "$module" = "fuse" -o "$module" = "cuse" ]; then
			sleep 1
			echo "Checking if there are any fusectl filesystems mounted" >> $OUTPUTFILE
			mount | grep "^fusectl on" >> $OUTPUTFILE
			if [ $? -eq 0 ]; then
				echo "Trying to umount all fusectl filesystems" >> $OUTPUTFILE
				mount | grep "^fusectl on" | awk '{print $3}' | xargs -i{} umount {}
			fi
		fi

		mlog "echo \"** Attempting to unload $module... **\"" /dev/console "$OUTPUTFILE"
		/sbin/modprobe -r $module  >> $OUTPUTFILE 2>&1
		RC=$?
		if [ $RC -ne 0 ] ; then
			echo "** Modprobe FAILED, exit: $RC **"  >> $OUTPUTFILE
			echo "** Mounted filesystems at the moment of failure: " >> $OUTPUTFILE
			mount 2>&1 >> $OUTPUTFILE

			# Bug 1031165 - Dependency issue with Intel hw specific serpent crypto modules
			if [ "$module" = "serpent" ]; then
				echo "** Ignoring failure, known issue, see Bug 1031165" >> $OUTPUTFILE
				continue
			else
				fail=$(expr $fail + 1)
			fi
		fi

		for k in $(seq 1 3); do
			if [ $(/sbin/lsmod | grep -c $module) -eq 0 ] ; then
				echo "** $module removed sucessfully. **" >> $OUTPUTFILE
				pass=$(expr $pass + 1)
				break
			fi
			sleep 1
		done

		# workaround for Bug 1247156 - NM/udev rules prevent unloading of some kernel modules
		if [ -e "/sys/module/$module" ]; then
			mod_time2=$(stat --format='%y' "/sys/module/$module")
			if [ "$mod_time1" != "$mod_time2" ]; then
				echo "** $module appears to be re-loaded, assuming this is Bug 1247156 **" >> $OUTPUTFILE
				pass=$(expr $pass + 1)
				continue
			fi
		fi

		if [ $(/sbin/lsmod | grep -c $module) -ne 0 ] ; then
			fail=$(expr $fail + 1)
			echo "** $module FAILED to un-load. **" >> $OUTPUTFILE
			echo "** Attempting 2nd unload **" >> $OUTPUTFILE
			/sbin/modprobe -r $module  >> $OUTPUTFILE 2>&1
			if [ $(/sbin/lsmod | grep -c $module) -ne 0 ] ; then
				echo "** 2nd attempt to unload failed too **" >> $OUTPUTFILE
			fi
		fi
	done
	/sbin/lsmod >> $OUTPUTFILE 2>&1
	RC=$?
	if [ $RC -ne 0 ] ; then
		echo "** There is a problem with lsmod exit: $RC **"  >> $OUTPUTFILE
		fail=$(expr $fail + 1)
	else
		pass=$(expr $pass + 1)
	fi
	sleep 5
done

# restore message verbosity
echo $printk_default > /proc/sys/kernel/printk

# Check our results
echo "** $fail failures, $pass passes, $skip modules skipped, $ITERATIONS iterations **" >> $OUTPUTFILE
echo "*** End of test. ***" >> $OUTPUTFILE
if [ $fail -eq 0 ] && [ $pass -gt 0 ] ; then
	result_pass
else
	result_fail
fi


# something  bad must have happened, otherwise we should not get here.
echo "Unhandled exception or other problem, results not reliable!" >> $OUTPUTFILE
result_fail
