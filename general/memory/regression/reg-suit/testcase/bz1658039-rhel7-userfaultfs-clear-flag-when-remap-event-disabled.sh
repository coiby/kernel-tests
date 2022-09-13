#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Clear wrong flags in userfaultfd mremap.
#   Description:
#   Author: Ping Fang <pifang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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


function bz1658039()
{
	yum install -y expect
	if rlIsRHEL "7" && [[ "$(uname -m)" = "s390x" ]]; then
		return 0;
	fi
	if ! rlRun "gcc -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"; then
		return 1;
	fi
	local addr=$(unbuffer ./$FUNCNAME | head -n1 | sed -ue 's/\([a-z A-Z]*: 0x\)//' &)
	local case_pid=$(pidof $FUNCNAME)
	local flags=$(awk -v addr=$addr- 'BEGIN{s=0} $0~addr { s=1 }  { if (($0 ~ /VmFlags/) && (s == 1)) {print $0; exit(0)}}' /proc/$case_pid/smaps)
	rlLog "$flags"
	rlAssertNotGrep "u[mw]" <(echo $flags)
	sleep 100
}
