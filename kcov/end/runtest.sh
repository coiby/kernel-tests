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

. /usr/bin/rhts_environment.sh

. ../include/include.sh

TEST="/kcov/end"

log "loading config from $KCOV_CONF"
# set KDIR_OPT, KCOV_TEST_NAME, KCOV_TEST_INFO
load_config

# clean up reboot_hook() in start/runtest.sh
function reboot_cleanup()
{
	local REBOOTBIN=`which reboot`
	local RHTSREBOOTBIN=`which rhts-reboot`

	rm -f /etc/dracut.conf.d/gcov.conf
	mv ${REBOOTBIN}.bak ${REBOOTBIN}
	mv ${RHTSREBOOTBIN}.bak ${RHTSREBOOTBIN}
}

reboot_cleanup

log "$KCOV_TEST_NAME has finished, collecting the coverage data."

lcov --capture $KDIR_OPT --test-name "$KCOV_TEST_NAME" --output-file $KCOV_TEST_INFO
if [ $? -ne 0 ]; then
	# Add "--ignore-error gcov" to workaround
	# Bug 1817991 - gcov: internal compiler error: in handle_cycle, at gcov.c:627
	log "Fail to capture coverage data, trying to add '--ignore-error gcov' to workaround"
	lcov --ignore-error gcov --capture $KDIR_OPT --test-name "$KCOV_TEST_NAME" --output-file $KCOV_TEST_INFO
	if [ $? -ne 0 ]; then
		log "Fail to capture coverage data with '--ignore-error gcov'"
		fail
		exit 1
	fi
fi

if [ ! -f $KCOV_TEST_INFO ]; then
	fail check_kcov_test_info "kcov test info file does not exists."
	exit 1
fi
ls -allh $KCOV_TEST_INFO
log "submit the coverage data file $KCOV_TEST_INFO"
submit_info $KCOV_TEST_INFO

log "Combine baseline and test coveraged data."
if [ ! -f $KCOV_BASE_INFO ]; then
	fail check_base_info "base cov data does not exists."
	exit 1
fi
REBOOT_TRACE_ARGS=""
for gdata in ${KCOV_TEST_INFO}.reboot*; do
	if [[ $gdata != "${KCOV_TEST_INFO}.reboot*" ]]; then
		submit_info $gdata
		REBOOT_TRACE_ARGS+=" --add-tracefile $gdata "
	fi
done
lcov --add-tracefile $KCOV_BASE_INFO $REBOOT_TRACE_ARGS --add-tracefile $KCOV_TEST_INFO --output-file $KCOV_ALL_INFO
echo "$KCOV_ALL_INFO" >> $KCOV_INFO_LIST
log "Submit combined trace info for $KCOV_TEST_NAME"
submit_info $KCOV_ALL_INFO

pass
