#!/bin/sh

# Copyright (c) 2010 Red Hat, Inc. All rights reserved. This copyrighted material 
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
# Author: Hushan Jia <hjia@redhat.com>

. /usr/bin/rhts_environment.sh

# source include file
. ../include/include.sh

RHEL=$(sed -ne's/^Red Hat.*release \([0-9]\.[0-9]\).*$/\1/p' /etc/redhat-release)
MAJOR=$(echo $RHEL | cut -c1)
MINOR=$(echo $RHEL | cut -c3)
VERSION=${RHEL_KRNL[$MAJOR$MINOR]}

setup()
{
	KN=kernel
	GCOVRPM=$KN-$VERSION.gcov.$(arch).rpm
	GCOVCORERPM=$KN-core-$VERSION.gcov.$(arch).rpm
	GCOVMODULESRPM=$KN-modules-$VERSION.gcov.$(arch).rpm
	GCOVURL="$REPO/$VERSION.gcov/$(arch)/$GCOVRPM \
		 $REPO/$VERSION.gcov/$(arch)/$GCOVCORERPM \
		 $REPO/$VERSION.gcov/$(arch)/$GCOVMODULESRPM"
	GCOVDARPM=$KN-gcov-$VERSION.gcov.$(arch).rpm
	GCOVDAURL=$REPO/$VERSION.gcov/$(arch)/$GCOVDARPM

	# prepare the kernel for coverage collection
	log "Red Hat release: $(cat /etc/redhat-release)"
	log "Running on $(arch), kernel $(uname -r)"
	log "gcov kernel to download is $GCOVURL"

	# setting configs
	log "setting configs"
        if [ -n "$KDIR" ]; then
		KCOV_KDIR=$KDIR
        fi


	log "write config"
	echo "KDIR=$KCOV_KDIR" > $KCOV_CONF
	if [ -n "$ONLY_FINAL_INFO" ]; then
		echo "ONLY_FINAL_INFO=$ONLY_FINAL_INFO" >> $KCOV_CONF
	fi
	log "submit config"
	rhts-submit-log -l $KCOV_CONF


	rm -rf $TDIR/$GCOVRPM
	wget -P $TDIR $GCOVURL > /dev/null
	if [ $? -ne 0 ]; then
		fail "prepare" "Cannot download the gcov kernel.";
		exit
	fi

	rm -rf $TDIR/$GCOVDARPM
	wget -P $TDIR $GCOVDAURL > /dev/null
	if [ $? -ne 0 ]; then
		fail "prepare" "Cannot download the gcov graph files.";
		exit
	fi


	log "install kcov kernel"
	rpm -ivh --force $TDIR/$GCOVRPM $TDIR/$GCOVCORERPM $TDIR/$GCOVMODULESRPM
	if [ $? -ne 0 ]; then
		fail prepare "Cannot install the kcov kernel package.";
		exit
	fi

	log "install gcov data files"
	rpm -ivh $TDIR/$GCOVDARPM
	if [ $? -ne 0 ]; then
		fail prepare "Cannot install the gcov data files package.";
		exit
	fi

	install_lcov

	# Enable NFS service on startup to make sure sunrpc module is loaded,
	# otherwise we see errors like
	# "lcov: ERROR: subdirectory net/sunrpc not found" in kcov/end if
	# "net/sunrpc" is in KDIR, but the test didn't load it.
	# This is just a workaround
	chkconfig nfs on >/dev/null 2>&1
	systemctl enable nfs-server >/dev/null 2>&1

	# gcov needs tens of hours to process xfs_sb.c on RHEL7, workaround it
	# by setting geninfo_gcov_all_blocks = 0 to /etc/lcovrc
	# see Bug 1290759 for details
	echo "geninfo_gcov_all_blocks = 0" >> /etc/lcovrc

	log "current boot kernel is: $(grubby --default-kernel)"
	log "change boot kernel to gcov kernel"
	grubby --set-default=$KCOV_IMG
	log "new boot kernel is: $(grubby --default-kernel)"
	log "reboot to gcov kernel"

	rhts-reboot
}

verify()
{
	log "after reboot"
	log "current kernel is $(uname -r)"
	uname -r | grep gcov
	if [ $? -ne 0 ]; then
		fail "prapare" "not running on gcov kernel."
		fail
		exit
	fi

	log "ok, going on the coverage testing..."

	mount | grep debugfs
	if [ $? -ne 0 ]; then
		mount none /sys/kernel/debug -t debugfs
	fi
	log "proc entries: $(ls /sys/kernel/debug/gcov)"

	pass
}

if [ -z "$REBOOTCOUNT" ] || [ "$REBOOTCOUNT" -eq 0 ]; then
	setup
else
	verify
fi
