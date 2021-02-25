#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Set the full test name
TEST="/kernel/distribution/selinux-custom-modules"

rlJournalStart
  rlPhaseStartTest
    if rlIsRHEL 8.4 && [ $(uname -m) == "aarch64" ]; then
      rlRun "make -f /usr/share/selinux/devel/Makefile kexec.pp" 0 "Building kexec SELinux module"
      # Bug 1896424 - [RHEL-8.4] selinux denies kexec write on aarch64
      rlRun "semodule -i kexec.pp" 0 "Installing kexec SELinux module"
    elif rlIsRHEL 9 || rlIsFedora; then
      # Bug 1910373 - selinux avc denials for rhsmcertd-worke and rpcbind
      rlRun "make -f /usr/share/selinux/devel/Makefile rpcbind-mod.pp" 0 "Building rpcbind SELinux module"
      rlRun "make -f /usr/share/selinux/devel/Makefile rhsmcertd-worke.pp" 0 "Building rhsmcertd-worke SELinux module"
      # Bug 1923006 - [RHEL-9] avc: denied { node_bind } for pid=31097 comm="rhsmcertd-worke"
      rlRun "make -f /usr/share/selinux/devel/Makefile rhsmcertd-worke-nodebind.pp" 0 "Building rhsmcertd-worke-nodebind SELinux module"
      # Bug 1913372 - selinux avc denials for systemd-logind
      rlRun "make -f /usr/share/selinux/devel/Makefile systemd-logind-mod.pp" 0 "Building systemd-logind SELinux module"
      # Bug 1931470 - avc: denied { fowner } comm="groupadd" comm="mandb" capability=3
      rlRun "make -f /usr/share/selinux/devel/Makefile groupadd.pp" 0 "Building groupadd SELinux module"
      rlRun "make -f /usr/share/selinux/devel/Makefile mandb-mod.pp" 0 "Building mandb SELinux module"
      # Bug 1929329 - [RHEL-9] avc: denied { watch } for pid=328374 comm="avahi-daemon"
      rlRun "make -f /usr/share/selinux/devel/Makefile avahi-daemon.pp" 0 "Building avahi-daemon SELinux module"
      # Bug 1929332 - [RHEL-9] avc: denied { integrity } for pid=11514 comm="ioperm01"  and comm="grep"
      rlRun "make -f /usr/share/selinux/devel/Makefile ioperm01.pp" 0 "Building ioperm01 SELinux module"
      # Bug 1932436 - avc denied related to sssd and systemd-hostname
      rlRun "make -f /usr/share/selinux/devel/Makefile sssd-mod.pp" 0 "Building sssd SELinux module"
      rlRun "make -f /usr/share/selinux/devel/Makefile systemd-hostnam-mod.pp" 0 "Building systemd-hostname SELinux module"
      rlRun "semodule -i rpcbind-mod.pp -i rhsmcertd-worke.pp rhsmcertd-worke-nodebind.pp systemd-logind-mod.pp groupadd.pp mandb-mod.pp avahi-daemon.pp ioperm01.pp sssd-mod.pp systemd-hostnam-mod.pp" 0 "Installing SELinux modules"
    else
      rlLog "No custom SELinux modules required, skipping"
      rstrnt-report-result $TEST SKIP
      exit
    fi
  rlPhaseEnd
rlJournalPrintText
rlJournalEnd
