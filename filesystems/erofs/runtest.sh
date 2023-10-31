#!/bin/bash
#
# Copyright (c) 2023 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.
#
. /usr/share/beakerlib/beakerlib.sh || exit 1

WORKING_DIR=/tmp/erofs
OUTPUTFILE="/var/tmp/MAKERESULTS.log"
touch "${OUTPUTFILE}" || exit 1
rlJournalStart
  rlPhaseStartTest
    git clone https://github.com/erofs/erofs-utils.git "${WORKING_DIR}"
    cd $WORKING_DIR || exit
    git checkout experimental-tests
    autoupdate
    ./autogen.sh
    ./configure --disable-lz4
    export srcdir="$WORKING_DIR"/tests/erofs

    rlRun "make check > ${OUTPUTFILE}"
    if grep -q "FAIL: erofs/[0-9]\+" "${OUTPUTFILE}"; then
      rstrnt-report-result -o "${OUTPUTFILE}" filesystems/erofs FAIL
    else
      rstrnt-report-result -o "${OUTPUTFILE}" filesystems/erofs PASS
    fi
  rlPhaseEnd
rlJournalEnd
