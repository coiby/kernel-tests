#!/bin/bash
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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

# Turn off the POSIX to avoid syntax errors
set +o posix

. ../../automotive/include/rhivos.sh
. ../../cmdline_helper/libcmd.sh
. ../include/lib.sh
. ../include/kdump.sh
. ../include/kdump-multi.sh
. ../include/crash.sh
. ../include/tmt.sh

# This is to allow loading an extra/internal lib file

RESOURCE_URL=${RESOURCE_URL:-""}
if [ -n "$RESOURCE_URL" ]; then
    lib_file="${RESOURCE_URL##*/}"
    [ ! -f "$lib_file" ] && curl -LO --fail "$RESOURCE_URL"
    if [ -f "$lib_file" ]; then
        # To bypass ShellCheck SC1090
        # shellcheck source=./
        . ./"$lib_file"
    else
        Warn "Failed to download the lib file $RESOURCE_URL."
    fi
fi





