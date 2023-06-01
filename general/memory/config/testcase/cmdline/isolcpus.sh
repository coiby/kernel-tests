#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description:
#   Author: Wang Shu <shuwang@redhat.com>
#   Update: MM-QE <mm-qe@redhat.com>
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

function check_cpu()
{
    local isolcpus
    local cpu
    isolcpus=`awk -v RS=" " '/isolcpus/' /proc/cmdline`
    isolcpus=${isolcpus##isolcpus=}
    echo $isolcpus | grep -q '-'
    if [ $? == 0 ]; then          # remove hyphen, isolcpus=1-7
        isolcpus=`echo $isolcpus | sed  's/-/\ /g'`
        isolcpus=`seq $isolcpus`
    fi
    isolcpus=`echo $isolcpus | sed 's/,/\ /g'`   # remove comma, isolcpus=1,3,5,7
    for cpu in $isolcpus
    do
        rlAssert0 "Assert no user process on CPU${cpu}" `ps -mo psr,command --ppid 2 -p 2 --deselect | grep "^  $cpu -" | wc -l`
    done

}

function isolcpus()
{
    local cores
    local max_core
    cores=`lscpu | grep '^CPU(s):' | awk '{print $2}'`
    if [ "$cores" == "1" ]; then
        rlLog "isolcpus is only for SMP."
        return 0
    fi
    setup_cmdline_args "isolcpus=0" ZERO && check_cpu
    max_core=$((cores-1))
    if [ $max_core -gt 1 ]; then
        setup_cmdline_args "isolcpus=1-$max_core" HYPHON && check_cpu
        setup_cmdline_args "isolcpus=`seq -s , 1 $max_core`" COMMA && check_cpu
    fi
    if rlIsRHEL ">=6.10"; then
        setup_cmdline_args "isolcpus=1-10000" OVERFLOW
        if rlIsRHEL ">=8"; then
            rlAssertGrep "Housekeeping: nohz_full= or isolcpus= incorrect CPU range" <(journalctl -kb)
        elif rlIsRHEL ">7.2"; then
            rlRun "cat /var/log/messages /var/log/dmesg | grep 'sched: Error, all isolcpus= values must be between 0 and'" #bz1304216
        fi
    fi
    cleanup_cmdline_args "isolcpus"
}
