#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/memory/function/mem_encrypt
#   Description: mem_encrypt test for AMD SME
#   Author: Ping Fang <pifang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include rhts environment
. /usr/bin/rhts-environment.sh      || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

set -o pipefail

firstboot=/mnt/testarea/mem_encrypt_firstboot
kname=$(rpm -qf --qf "%{name}\n" /boot/vmlinuz-$(uname -r) | sed 's/-core//g')
kversion=$(rpm -qf --qf "%{version}\n" /boot/vmlinuz-$(uname -r))
krelease=$(rpm -qf --qf "%{release}\n" /boot/vmlinuz-$(uname -r))

rlJournalStart
	rlPhaseStartTest
	if grep mem_encrypt=on /proc/cmdline ; then
		rlLog "already set"
		grep "\<SME\>" <(journalctl -kb) || return 0
	elif [ ! -e $firstboot ]; then
		rlRun "grubby --args mem_encrypt=on --update-kernel DEFAULT"
		rlRun "touch $firstboot"
		rhts-reboot
	fi
	rpm -q ${kname}-devel-${kversion}-${krelease} || rlRpmInstall ${kname}-devel $kversion $krelease "$(uname -m)"
	rpm -q ${kname}-devel-${kversion}-${krelease} || rlDie "no ${kname}-devel package available"
	rlRun "insmod sme_module/sme_test.ko" 1
	rlRun "dmesg | grep SMEtest | awk '{print \$5,\$6,\$7,\$8,\$9,\$10,\$11,\$12}' | grep -v deadbeef" 0
	rlRun "dmesg -C"
	if [ -e $firstboot ]; then
		rlRun "grubby --remove-args mem_encrypt=on --update-kernel DEFAULT"
		rlRun "rm $firstboot"
		rhts-reboot
	fi
	rlPhaseEnd
rlJournalPrintText
rlJournalEnd
