#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
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

FILE=$(readlink -f ${BASH_SOURCE[0]})
NAME=$(basename $FILE)
CDIR=$(dirname $FILE)

# This example uses beakerlib framework, include the library
source /usr/share/beakerlib/beakerlib.sh

# Include enviroment and libraries
source $CDIR/../cki_lib/libcki.sh || exit 1

function startup
{
    rlLog "$NAME: startup"
    return 0
}

function cleanup
{
    rlLog "$NAME: cleanup"
    return 0
}

function runtest
{
    rlLog "$NAME: runtest"
    rlLog "This this is an example test which always passes"
    return 0
}

cki_main
exit $?
