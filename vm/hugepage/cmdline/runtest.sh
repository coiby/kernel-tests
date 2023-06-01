#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/vm/hugepage/cmdline
#   Description: hugepages from cmdline
#   Author: Caspar Zhang <czhang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
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

# Testcase #1:
#   hugepages= option (for all)
# Testcaes #2:
#   hugepagesz= option (for RHEL6|7 x86_64, ia64, ppc64)

MEMINFO=/proc/meminfo
PROCFS_PATH=/proc/sys/vm
SYSFS_PATH=/sys/kernel/mm/hugepages
RESTORE_FILE=/mnt/testarea/restore_file

cat /proc/filesystems | grep -q hugetlbfs
if [ $? -ne 0 ]; then
# Bug 1143877 - hugetlbfs: disabling because there are no supported hugepage sizes
	echo "hugetlbfs not found in /proc/filesystems, skipping test"
	report_result Test_Skipped PASS 99
	exit 0
fi

hpsz="$(cat /proc/meminfo | grep Hugepagesize | awk '{print $2}')"
# HP_SIZE for ia64 is too big (256M)
test ${ARCH} = ia64 && HP_NR=20 || HP_NR=50
# HP_SIZE for aarch64 is too big (512M or 2M)
test ${ARCH} = aarch64 && test ${hpsz} = "524288" && HP_NR=2

MULTI_HP=NO
CMDLINEARGS="hugepages=${HP_NR}"
if [ ${ARCH} = x86_64 ] || [ ${ARCH} = ppc64 ] || [ ${ARCH} = aarch64 ]; then
	if (egrep -q '(release 6|release 7|release 8|release 9)' /etc/redhat-release) &&
		(grep -q 'pdpe1gb' /proc/cpuinfo); then
		MULTI_HP=YES
		CMDLINEARGS="hugepages=${HP_NR} hugepagesz=1G hugepages=1"
	fi
fi

# Restore CMDLINE
if [ ! -z $REBOOTCOUNT ] && [ $REBOOTCOUNT -gt 1 ]; then
	cat /proc/cmdline | tee -a $OUTPUTFILE
	if ! grep -q "$CMDLINEARGS" /proc/cmdline; then
		report_result "restore_cmdline" "PASS" 0
		exit 0
	else
		report_result "restore_cmdline" "FAIL" 0
		exit 1
	fi
fi

# Set CMDLINE
make -C /mnt/tests/kernel/cmdline CMDLINEARGS="$CMDLINEARGS" run

# Start Test
rm -f $OUTPUTFILE
touch $OUTPUTFILE
RESULT="PASS"
TEST=hugepage-cmdline

# From /proc/meminfo
echo " + check results from ${MEMINFO}" | tee -a $OUTPUTFILE
hp_total=`grep 'HugePages_Total' ${MEMINFO} | awk '{print $2}'`
echo " |- HugePages_Total = $hp_total" | tee -a $OUTPUTFILE
hp_free=`grep 'HugePages_Free' ${MEMINFO} | awk '{print $2}'`
echo " |- HugePages_Free = $hp_free" | tee -a $OUTPUTFILE
if [ "x$hp_total" != "x${HP_NR}" -o "x$hp_free" != "x${HP_NR}" ]; then
	echo " \`- check ${MEMINFO} failed" | tee -a $OUTPUTFILE
	RESULT=FAIL
else
	echo " \`- check /proc/meminfo passed" | tee -a $OUTPUTFILE
fi

# From procfs
echo " + check results from ${PROCFS_PATH}" | tee -a $OUTPUTFILE
hp_total=`cat ${PROCFS_PATH}/nr_hugepages`
echo " |- nr_hugepages = $hp_total" | tee -a $OUTPUTFILE
if [ "x$hp_total" != "x${HP_NR}" ]; then
	echo " \`- check ${PROCFS_PATH} failed" | tee -a $OUTPUTFILE
	RESULT=FAIL
else
	echo " \`- check ${PROCFS_PATH} passed" | tee -a $OUTPUTFILE
fi

# From sysfs
if egrep -q '(release 6|release 7|release 8)' /etc/redhat-release; then
	HP_SIZE=`grep 'Hugepagesize' ${MEMINFO} | awk '{print $2}'`
	echo " + check results from ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/" | tee -a $OUTPUTFILE
	hp_total=`cat ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/nr_hugepages`
	echo " |- nr_hugepages = $hp_total" | tee -a $OUTPUTFILE
	hp_free=`cat ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/free_hugepages`
	echo " |- free_hugepages = $hp_free" | tee -a $OUTPUTFILE
	if [ "x$hp_total" != "x${HP_NR}" -o "x$hp_free" != "x${HP_NR}" ]; then
		echo " \`- check ${SYSFS_PATH} failed" | tee -a $OUTPUTFILE
		RESULT=FAIL
	else
		echo " \`- check ${SYSFS_PATH} passed" | tee -a $OUTPUTFILE
	fi

	if [ ${MULTI_HP} = YES ]; then
		result_appendix="-1G"
		HP_SIZE=1048576 # 1GB
		echo " + check results from ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/" | tee -a $OUTPUTFILE
		hp_total=`cat ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/nr_hugepages`
		echo " |- nr_hugepages = $hp_total" | tee -a $OUTPUTFILE
		hp_free=`cat ${SYSFS_PATH}/hugepages-${HP_SIZE}kB/free_hugepages`
		echo " |- free_hugepages = $hp_free" | tee -a $OUTPUTFILE
		if [ "x$hp_total" != "x1" -o "x$hp_free" != "x1" ]; then
			echo " \`- check ${SYSFS_PATH} failed" | tee -a $OUTPUTFILE
			RESULT=FAIL
		else
			echo " \`- check ${SYSFS_PATH} passed" | tee -a $OUTPUTFILE
		fi
	fi
fi

if [ "${RESULT}" = "PASS" ]
then
	report_result "${TEST}${result_appendix}" ${RESULT}
else
	report_result "${TEST}${result_appendix}" ${RESULT} 1
fi

# Restore CMDLINE
rm -f $OUTPUTFILE
touch $OUTPUTFILE
default=$(/sbin/grubby --default-kernel)
/sbin/grubby --remove-args="${CMDLINEARGS}" --update-kernel="${default}"
if [ "${ARCH}" = "s390" ] || [ "${ARCH}" = "s390x" ]; then
	/sbin/zipl
fi
echo "Reboot to restore cmdline" | tee -a $OUTPUTFILE
rhts-reboot
