#!/bin/sh

# Copyright (C) 2008 CAI Qian <caiqian@redhat.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
# Update: Qiao Zhao <qzhao@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

analyse()
{
    GetCorePath

    #########################
    # 1. Analyse by readelf #
    #########################
    # shellcheck disable=SC2154
    Log "Run cmd: readelf -a ${vmcore}"
    readelf -a "${vmcore}" 2>&1 | tee ${K_TESTAREA}/readelf.log
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        Error "readelf returns errors."
    fi

    # Catch warnings like,
    #     # readelf: Warning: corrupt note found at offset e40 into core
    #         # notes
    if grep -iw -e 'warning' -e 'warnings' ${K_TESTAREA}/readelf.log; then
        Error "readelf returns warnings."
    fi
    RhtsSubmit ${K_TESTAREA}/readelf.log

    #########################
    # 2. Analyse by objdump #
    #########################
    echo "Run cmd: objdump -x ${vmcore}"
    objdump -x "${vmcore}" 2>&1 | tee ${K_TESTAREA}/objdump.log
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        Error "objdump returns errors."
    fi
    RhtsSubmit ${K_TESTAREA}/objdump.log

    ############################
    # 3. Analyse by eu-readelf #
    ############################
    Log "Run cmd: eu-readelf -a ${vmcore}"
    eu-readelf -a "${vmcore}" 2>&1 | tee ${K_TESTAREA}/eu-readelf.log
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        Error "eu-readelf returns errors."
    fi
    RhtsSubmit ${K_TESTAREA}/eu-readelf.log
}

#+---------------------------+

Multihost "analyse"
