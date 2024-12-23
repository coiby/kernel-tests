#! /bin/bash
#  vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   /kernel/general/scheduler/1388158-*
#   Description: docker swarm init and docker swarm leave panic kernel
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc.
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

. /usr/share/beakerlib/beakerlib.sh ||  exit 1

if [ -z "$OUTPUTFILE" ]; then
	export OUTPUTFILE=`mktemp /mnt/testarea/tmp.XXXXXX`
fi

export TEST=/kernel/general/scheduler/1388158-panic-by-use-freed-autogroup
trap 'Cleanup' SIGHUP SIGINT SIGQUIT SIGTERM SIGUSR1

tracing_dir=/sys/kernel/debug/tracing
nr_cpu=$(cat /proc/cpuinfo | grep -w ^processor | wc -l)
max=$((nr_cpu - 1))

rlJournalStart
	rlPhaseStartSetup
		rlRun "gcc reproducer.c -o reproducer"
	rlPhaseEnd

	rlPhaseStartTest
		./reproducer &
		pid=$!
		rlReport "autogroup-free" PASS
		sleep 60
		kill $pid
	rlPhaseEnd
rlJournalEnd
rlJournalPrintText

