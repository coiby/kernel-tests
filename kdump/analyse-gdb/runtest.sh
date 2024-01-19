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

# Source Kdump tests common functions.
. ../include/runtest.sh

analyse()
{
    GetCorePath
    CheckVmlinux
    LsCore

    # Analyse by gdb
    rpm -q --quiet gdb || InstallPackages gdb
    LogRun "rpm -q gdb"
    # shellcheck disable=SC2154
    Log "# gdb < gdb.cmd ${vmlinux} ${vmcore} > ${K_TESTAREA}/gdb.log"
    gdb < gdb.cmd ${vmlinux} ${vmcore} > ${K_TESTAREA}/gdb.log 2>&1
    code=$?

    RhtsSubmit "$(pwd)/gdb.cmd"
    RhtsSubmit "${K_TESTAREA}/gdb.log"

    if [ ${code} -ne 0 ]; then
        Error "gdb returns error code ${code}."
    fi

    Log "Skip the following known GDB warnings.
- 'warning: shared library handler failed to enable breakpoint'"

    Log "Search for the following patterns for potential errors.
- 'fail'
- 'error'
- 'invalid'"

    if grep -v 'warning: shared library handler failed to enable\
 breakpoint' "${K_TESTAREA}/gdb.log" |
        grep -i -e 'fail' \
                -e 'error' \
                -e 'invalid' \
       >> "${OUTPUTFILE}" 2>&1; then

        Error "GDB commands reported failures. Read gdb.log for details."

    else
        Log "GDB commands succeeded"
    fi
}

#+---------------------------+

Multihost "analyse"
