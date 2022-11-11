#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/mce-test/mcelog
#   Description: mcelog functionality test
#   Author: Evan McNabb <emcnabb@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
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

# Include helper functions
. /mnt/tests/kernel/mce-test/include/runtest.sh

mcelog --is-cpu-supported 2>&1 >/dev/null
if [ "$?" -ne "0" ] ; then
    rlLogInfo "host CPU is not supported by mcelog, skipping this test set"
    rhts-report-result $TEST SKIP $OUTPUTFILE
    rlJournalEnd
    exit 0
fi

################# Setup #######################################################

# Install test suites
InstallMceInject
InstallPageTypes

# Prepare system
LoadMceInjectMod

# If we've gotten to here setup has passed
report_result "$TEST/setup" "PASS"

################# Test Logging Methods (trigger/mcelogd/crond) ################
# Inject errors and decode via trigger, mcelogd, and cron.

#----------- Trigger -----------------------------------
# Inject MCE and confirm an external script can be triggered
echo -e "\n==== Test logging via trigger ===="

# Disable cron/mcelogd so they won't process injected MCEs accidentally
service crond stop &>/dev/null
service $SERVICENAME stop &>/dev/null

rm -f /trigger.sh /var/log/mcelog.trigger
# External script to trigger:
cat << EOF > /trigger.sh
#!/bin/sh
/usr/sbin/mcelog --ignorenodev --filter >> /var/log/mcelog.trigger
EOF
chmod 755 /trigger.sh

# Activate trigger script and inject MCE
rhts-flush
echo "/trigger.sh" > /sys/devices/system/machinecheck/machinecheck0/trigger
address=`GenRandAddr`
echo "Injecting MCE, random address is: $address"
echo "CPU 0 BANK 0 STATUS CORRECTED ADDR 0x$address" |mce-inject
sleep 2

echo -e "Contents of /var/log/mcelog.trigger: \n---\n`cat /var/log/mcelog.trigger`\n---"
if `grep -q $address /var/log/mcelog.trigger`; then
    echo "MCE correctly logged"
    report_result "$TEST/trigger" "PASS"
else
    echo "MCE not logged correctly"
    report_result "$TEST/trigger" "FAIL"
fi

# Clean up
rm -f /trigger.sh /var/log/mcelog
echo > /sys/devices/system/machinecheck/machinecheck0/trigger

#----------- Daemon --------------------------------------
# Inject MCE and confirm mcelog daemon successfully logs via syslog

echo -e "\n==== Test logging via mcelogd ===="
service crond stop &>/dev/null
service $SERVICENAME restart ; echo ""

# Where to search for logged MCE
DAEMONLOGFILE=''
if `grep -q 'release 6\.' /etc/redhat-release`; then
        DAEMONLOGFILE='/var/log/mcelog'
else
        # RHEL7 and later
        DAEMONLOGFILE='/var/log/messages'
fi

# Inject MCE and confirm it was immediately logged to $DAEMONLOGFILE
rhts-flush
address=`GenRandAddr`
echo "Injecting MCE, random address is: $address"
logger "===> Beginning MCE injection"
echo "CPU 0 BANK 1 STATUS CORRECTED ADDR 0x$address" |mce-inject
sleep 2

echo -e "Contents of $DAEMONLOGFILE: \n---`tail -n 15 $DAEMONLOGFILE`\n---"
if `grep -q $address $DAEMONLOGFILE`; then
    echo "MCE correctly logged"
    report_result "$TEST/mcelogd" "PASS"
else
    echo "MCE not logged correctly"
    report_result "$TEST/mcelogd" "FAIL"
fi

# Clean up
rm -f /var/log/mcelog
service $SERVICENAME stop &>/dev/null

#----------- Cron --------------------------------------
# Inject MCE and confirm cron successfully processes it

# disabled for now; does not work --jdluhos

# echo -e "\n==== Test logging via cron ===="
# service $SERVICENAME stop &>/dev/null
# service crond start &>/dev/null

# # On RHEL7, cron is disabled in favor of mcelogd. Enable it and then disable
# # later.
# \cp -f /etc/cron.hourly/mcelog.cron /etc/cron.hourly/mcelog.cron.orig
# sed -i 's@#/usr/sbin/mcelog@/usr/sbin/mcelog@' /etc/cron.hourly/mcelog.cron

# # Clear out cron logfile and speed up cron script to run every minute
# echo > /var/log/mcelog
# echo '* * * * * root /etc/cron.hourly/mcelog.cron' >> /etc/crontab

# # Inject MCE, wait one minute, and see if cron decoded/logged it
# rhts-flush
# address=`GenRandAddr`
# echo "Injecting MCE, random address is: $address"
# echo "CPU 0 BANK 1 STATUS CORRECTED ADDR 0x$address" |mce-inject
# echo "Waiting one minute for crond to execute..."
# sleep 62

# echo -e "Contents of /var/log/mcelog: \n---`cat /var/log/mcelog`\n---"
# if `grep -q $address /var/log/mcelog`; then
#     echo "MCE correctly logged"
#     report_result "$TEST/cron" "PASS"
# else
#     echo "MCE not logged correctly"
#     report_result "$TEST/cron" "FAIL"
# fi

# # Clean up
# sed -i '/* * * * * root \/etc\/cron.hourly\/mcelog.cron/d' /etc/crontab
# \cp -f /etc/cron.hourly/mcelog.cron.orig /etc/cron.hourly/mcelog.cron
# rm -f /var/log/mcelog
# service $SERVICENAME restart &>/dev/null

#----------- Execute mcelog test suite --------------------------------------
# Execute mcelog's built in test suite. Available in mcelog SRC RPM.

echo -e "\n==== Running mcelog test suite ===="

# Download,
VER=`rpm -q --queryformat "%{VERSION}" mcelog`
REL=`rpm -q --queryformat "%{RELEASE}" mcelog`
wget -q -nc http://download.devel.redhat.com/brewroot/packages/mcelog/$VER/$REL/src/mcelog-$VER-$REL.src.rpm

# Extract,
BUILDROOT=`pwd`/mcelog-buildroot
mkdir -p $BUILDROOT
rpm -i --define "_topdir $BUILDROOT" mcelog-$VER-$REL.src.rpm
rpmbuild -bp --define "_topdir $BUILDROOT" $BUILDROOT/SPECS/mcelog.spec

# Run,
cd $BUILDROOT/BUILD/mcelog-*/tests/
# (use mcelog included in distro, not from SRC RPM)
sed -i 's#../../mcelog#/usr/sbin/mcelog#' test
echo "========================== mcelog test suite output START: =========================="
rhts-flush
make test
RESULT=$?
echo "========================== mcelog test suite output END:   =========================="

# Check results,
if [ "$RESULT" -eq 0 ]; then
    echo "Test suite passed!"
    report_result "$TEST/mcelog-testsuite" "PASS"
else
    echo "Test suite failed!"
    report_result "$TEST/mcelog-testsuite" "FAIL"
fi

#----------- Check for processor enablement --------------------------------------
# Double check that the processor specific decoding is enabled for this CPU

echo -e "\n========================== Check for processor enablement: =========================="
echo 'Searching for the string: Family __ Model __ CPU: only decoding architectural errors'
tail -n 175 /var/log/messages | grep -q "CPU: only decoding architectural errors"
if [ $? -eq 0 ]; then
    echo "String found, FAIL."
    echo 'This could indicate mcelog needs to be updated to support this processor.'
    report_result "$TEST/supported_cpu" "FAIL"
else
    echo "String not found, PASS."
    report_result "$TEST/supported_cpu" "PASS"
fi

# Clean up
rm /var/run/mcelog-client

echo "*** End of runtest.sh ***"
