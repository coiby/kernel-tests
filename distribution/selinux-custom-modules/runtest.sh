#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Set the full test name
TEST="/kernel/distribution/selinux-custom-modules"

rlJournalStart
  rlPhaseStartTest
    # Bug 1896424 - [RHEL-8.4] selinux denies kexec write on aarch64
    # https://bugzilla.redhat.com/show_bug.cgi?id=1896424
    if rlIsRHEL 8.4 && [ $(uname -m) == "aarch64" ]; then
      rlRun "make -f /usr/share/selinux/devel/Makefile kexec.pp" 0 "Building kexec SELinux module"
      rlRun "semodule -i kexec.pp" 0 "Installing kexec SELinux module"
    # Bug 1910373 - selinux avc denials for rhsmcertd-worke and rpcbind
    # https://bugzilla.redhat.com/show_bug.cgi?id=1910373
    elif rlIsRHEL 9; then
      rlRun "make -f /usr/share/selinux/devel/Makefile rpcbind-mod.pp" 0 "Building rpcbind-mod SELinux module"
      rlRun "make -f /usr/share/selinux/devel/Makefile rhsmcertd-worke.pp" 0 "Building rhsmcertd-worke SELinux module"
      rlRun "semodule -i rpcbind-mod.pp -i rhsmcertd-worke.pp" 0 "Installing rhsmcertd-worke and rpcbind-mod.pp SELinux modules"
    else
      rlLog "No custom SELinux modules required, skipping"
      rstrnt-report-result $TEST SKIP
      exit
    fi
  rlPhaseEnd
rlJournalPrintText
rlJournalEnd
