#!/bin/sh

# Copyright (c) 2009 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Hushan Jia<hjia@redhat.com>

. ../../../common/include.sh
. ../../../../cki_lib/libcki.sh

tunctl_install
RESULT=PASS
SCORE=0

TUNDEV=/dev/net/tun
TSTUSER=testuser1

cki_debug

report_fail()
{
	MSG=$1

	echo "FAIL: $MSG" | tee -a $OUTPUTFILE

	RESULT=FAIL
	rstrnt-report-result "$RSTRNT_TASKNAME" "$RESULT" "$SCORE"
}

loadmod()
{
	if [ -c $TUNDEV ]; then
		return 0
	fi

	modprobe tun 2>&1 | tee -a $OUTPUTFILE || (report_fail "load tun driver failed."; exit 1)
}

setup()
{
	echo "setup......" | tee -a $OUTPUTFILE
	echo "add user $TSTUSER" | tee -a $OUTPUTFILE
	useradd $TSTUSER
	if [ $? -ne 0 ]; then
		report_fail "create test user failed, quit."
		exit 1
	fi
}

cleanup()
{
	userdel -r -f $TSTUSER

	tunctl -d tun_a
	tunctl -d tap_a
	tunctl -d tun_an
	tunctl -d tap_an
}

run_log()
{
	CMD=$1
	FAIL=$2

	echo "Running \"$CMD\"" | tee -a $OUTPUTFILE
	$CMD >> $OUTPUTFILE 2>&1
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$FAIL, return code is $RC." | tee -a $OUTPUTFILE
		return 1
	fi

	return 0
}

run_log_user()
{
	CMD=$1
	FAIL=$2

	echo "Running \"$CMD\" as $TSTUSER" | tee -a $OUTPUTFILE
	su -c "$CMD" - $TSTUSER >> $OUTPUTFILE 2>&1
	RC=$?
	if [ $RC -ne 0 ]; then
		echo "$FAIL, return code is $RC." | tee -a $OUTPUTFILE
		return 1
	fi

	return 0
}

check_dev()
{
	DEV=$1

	echo "Running \"ifconfig $DEV\"" | tee -a $OUTPUTFILE
	ifconfig $DEV >> $OUTPUTFILE 2>&1
	if [ $? -ne 0 ]; then
		echo "FAIL: interface $DEV does not exists." | tee -a $OUTPUTFILE
		return 1
	else
		echo "Running \"ifconfig $DEV up\"" | tee -a $OUTPUTFILE
		ifconfig $DEV up >> $OUTPUTFILE 2>&1
		if [ $? -ne 0 ]; then
			echo "FAIL: interface $DEV up failed." | tee -a $OUTPUTFILE
			return 1
		fi
	fi

	echo "interface $DEV exists and upped."
	return 0
}

test_attach()
{
	IFF=$1
	USER=$2

	/sbin/ifconfig $IFF up
	/sbin/ifconfig $IFF down

	return 1
}

test_perm_root_creat()
{
	echo "Test with root user:" | tee -a $OUTPUTFILE
	run_log "tunctl -n -t tun_a" "Create tun interface failed" || RESULT=FAIL
	run_log "check_dev tun_a" "device check failed" || RESULT=FAIL
	run_log "tunctl -p -t tap_a" "Create tap interface failed" || RESULT=FAIL
	run_log "check_dev tap_a" "device check failed" || RESULT=FAIL

	run_log "tunctl -n -t tun_b -u $TSTUSER" "Create tun interface failed" || RESULT=FAIL
	run_log "tunctl -p -t tap_b -g $TSTUSER" "Create tun interface failed" || RESULT=FAIL
}

test_perm_non_root_creat()
{
	echo "Test with non root user: $TSTUSER" | tee -a $OUTPUTFILE
	run_log_user "/usr/sbin/tunctl -n -t tun_an" "Create tun interface failed"
	if [ $? -eq 0 ]; then
		echo "FAIL: should fail to create tun interface." | tee -a $OUTPUTFILE
		RESULT=FAIL
	fi
	run_log_user "/usr/sbin/tunctl -p -t tap_an" "Create tap interface failed"
	if [ $? -eq 0 ]; then
		echo "FAIL: should fail to create tap interface." | tee -a $OUTPUTFILE
		RESULT=FAIL
	fi
}

test_perm_user_attach()
{
	IFF=$1
	USER=$2

	/sbin/ifconfig $IFF up
	/sbin/ifconfig $IFF down
}

# FIXME: It looks we have another test test_attach, but I don't know what's
# the purpose, so just skip it at present.
test_root()
{
	test_perm_root_creat
}

test_non_root()
{
	test_perm_non_root_creat
}

loadmod

ATTR=$(ls -l $TUNDEV)
PERM=$(echo $ATTR | awk '{print $1}')

echo "$TUNDEV:\n$ATTR" | tee -a $OUTPUTFILE

setup

test_root
test_non_root

cleanup

rstrnt-report-result "$RSTRNT_TASKNAME" "$RESULT" "$SCORE"
