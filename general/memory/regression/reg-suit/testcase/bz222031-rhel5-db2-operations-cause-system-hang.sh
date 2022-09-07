#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 222031
#   Description: madvisre REMOVE opertaion causes system hang. 
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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

BZ_INFO="madvise REMOVE hange"
function bz222031()
{
	if rlIsRHEL ">=5.0";then
		case $(rlGetPrimaryArch) in
			i386|x86_64|ppc64|ppc64le|s390x|aarch64)
				if ! rlRun "gcc -o $DIR_BIN/$FUNCNAME $DIR_SOURCE/bz222031-madvise-remove.c" 0-255; then
					mark_skip "$FUNCNAME compile failed"
					rlLogWarning "$FUNCNAME compiles failed"
					return 1;
				fi

				rlLogInfo "To see whether a softlockup will happen."
				for i in `seq 5`; do
					$DIR_BIN/$FUNCNAME
				done
				rlLogInfo "Got here, check the dmesg, most possible we are not soft locked."
			    ;;
			*)
				rlLogInfo "$(uname -m) is not intended to be tested."
			    ;;
		esac
	else
		rlLogWarning "The softlockup issue is resolved in RHEL5"
	fi
	return 0;
}
