#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Bug 168112
#   Description: 
#   Author: Chao Ye <cye@redhat.com>
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

function bz168112()
{
    case $(rlGetPrimaryArch) in
        x86_64)
            yum install glibc-devel.i686 glibc-devel.ppc
            rlRun "gcc -lpthread -o ${FUNCNAME}_m32 -m32 $DIR_SOURCE/${FUNCNAME}.c"
            rlRun "gcc -lpthread -o ${FUNCNAME}_m64 -m64 $DIR_SOURCE/${FUNCNAME}.c"
            rlRun "./${FUNCNAME}_m32"
            rlRun "./${FUNCNAME}_m64"
            ;;
        *)
            rlRun "gcc -lpthread -o $FUNCNAME $DIR_SOURCE/${FUNCNAME}.c"
            rlRun "./${FUNCNAME}"
            ;;
    esac

}
