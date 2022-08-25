#!/bin/bash

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

. ../include/include.sh

TEST="/kcov/start"

log "loading config from $KCOV_CONF"
# set KDIR_OPT, KCOV_KDIR, KCOV_TEST_NAME, KCOV_BASE_INFO, KCOV_ALL_INFO
load_config

# copied from /kernel/general/code-coverage/start/runtest.sh with modification
function reboot_hook()
{
	#hook up lcov capture with system reboot to avoid gcov data lose
	grep -q lcov /usr/bin/rstrnt-reboot
	if [ $? -eq 0 ]; then
		log "rstrnt-reboot has already been hacked"
		return 0
	fi

	log "hookup lcov with rstrnt-reboot"
	cp /usr/bin/rstrnt-reboot /usr/bin/rstrnt-reboot.bak
	sed -i "/shutdown -r/ilcov -c --ignore-errors gcov $KDIR_OPT --test-name \"$KCOV_TEST_NAME\" -o ${KCOV_TEST_INFO}.reboot$(date '+%y%m%d%H%M%S')" /usr/bin/rstrnt-reboot

	cat >reboot <<-'EOF'
	#!/bin/bash
	cat /proc/mounts  | grep -v 'rootfs' | grep -q ' / '
	if [ $? == 0 ]; then
	    rstrnt-reboot
	else
	    systemctl reboot
	fi
	EOF

	cat >gcov.conf <<-'EOF'
	install_optional_items+=" PATHTOREBOOT PATHTORSTRNTREBOOT"
	EOF

	#force to use rstrnt-reboot
	local REBOOTBIN=`which reboot`
	mv ${REBOOTBIN} ${REBOOTBIN}.bak
	cp ./reboot ${REBOOTBIN}
	chmod a+x ${REBOOTBIN}
	cp gcov.conf /etc/dracut.conf.d/
	sed -i "s|PATHTOREBOOT|$(which reboot).bin|g" /etc/dracut.conf.d/gcov.conf
	sed -i "s|PATHTORSTRNTREBOOT|$(which rstrnt-reboot)|g" /etc/dracut.conf.d/gcov.conf
}

reboot_hook

log "start collecting coverage on test case $KCOV_TEST_NAME"
log "capture the initial data as the baseline"

lcov --initial --capture --base-directory $GCOV_BASEDIR/ $KDIR_OPT --output-file $KCOV_BASE_INFO
if [ $? -ne 0 ]; then
	if [ -n "$KCOV_KDIR" ]; then
		log "Fail to capture initial base data for $KCOV_KDIR."
	else
		log "Fail to capture initial base data."
	fi
	fail
	exit
fi

log "submit the initial data file"
submit_info $KCOV_BASE_INFO

log "zero the gcov counters"
lcov --zerocounters

pass

