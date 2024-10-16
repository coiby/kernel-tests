#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel-tests/security/vulnerabilities
#   Description: Check vulnerabilities/* files for unmitigated CVEs
#   Author: Jeff Bastian <jbastian@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc.
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

. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart

  rlPhaseStartTest

    rlShowRunningKernel

    rlAssertExists /sys/devices/system/cpu/vulnerabilities || rlDie \
        "Kernel does not report vulnerabilities"

    cat /proc/cpuinfo > cpuinfo.log
    rlLog "Log /proc/cpuinfo"
    rlFileSubmit cpuinfo.log

    pushd /sys/devices/system/cpu/vulnerabilities
      rlRun "grep . * | sed 's/:/^/' | column -t -s^ | tee -a $OUTPUTFILE" 0 \
          "Log vulnerabilities status"

      for v in * ; do
        # Reference from mmio_stale_data, but other files have similar information.
        # https://docs.kernel.org/admin-guide/hw-vuln/processor_mmio_stale_data.html
        # This is done to address virtualization scenarios where the host has the microcode update applied,
        # but the hypervisor is not yet updated to expose the CPUID to the guest.
        if virt-what | grep -qi kvm && grep -q "Vulnerable: Clear CPU buffers attempted, no microcode" /sys/devices/system/cpu/vulnerabilities/$v; then
            # Ignore this as it is likely a problem on hypervisor and not on guest side.
            continue
        fi
        rlAssertNotGrep Vulnerable /sys/devices/system/cpu/vulnerabilities/$v
      done
    popd

  rlPhaseEnd

  rlJournalPrintText

rlJournalEnd
