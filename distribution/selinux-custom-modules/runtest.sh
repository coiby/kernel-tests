#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Set the full test name
TEST="/kernel/distribution/selinux-custom-modules"

rlJournalStart

  rlPhaseStartTest "Modify to generate audit records"
    rlRun "sed  -i '/-a task,never/d' /etc/audit/rules.d/audit.rules" 0 "Removing audit rule task"
    rlRun "echo '-w /etc/shadow -p w' >> /etc/audit/rules.d/audit.rules" 0 "Adding extra rule task"
    rlServiceStop auditd && rlServiceStart auditd
  rlPhaseEnd

  rlPhaseStartTest
    # https://gitlab.com/cki-project/kernel-tests/-/issues/528
    # Bug 1932849 - avc: denied { module_request } kmod="net-pf-10"
    if grep "ipv6.disable=1" /proc/cmdline ; then
      rlRun "setsebool -P domain_kernel_load_modules on" 0 "Mask problems with module_request due BZ1932849 when IPv6 is disabled"
    fi

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
      rlRun "make -f /usr/share/selinux/devel/Makefile fowner-sadc.pp" 0 "Building fowner-sadc SELinux module"
      rules="rpcbind-mod rhsmcertd-worke rhsmcertd-worke-nodebind systemd-logind-mod groupadd mandb-mod fowner-sadc"
      # Skip if watch* permissions still not available, like Fedora 33
      if seinfo --common file -x | grep -q watch ; then
          # Bug 1929329 - [RHEL-9] avc: denied { watch } for pid=328374 comm="avahi-daemon"
          rlRun "make -f /usr/share/selinux/devel/Makefile avahi-daemon.pp" 0 "Building avahi-daemon SELinux module"
          rules="${rules} avahi-daemon"
      fi
      # Fedora 33 doesn't have lockdown class
      if seinfo --class lockdown -x  | grep -q integrity ; then
          # Bug 1929332 - [RHEL-9] avc: denied { integrity } for pid=11514 comm="ioperm01"  and comm="grep"
          rlRun "make -f /usr/share/selinux/devel/Makefile ioperm01.pp" 0 "Building ioperm01 SELinux module"
          rules="${rules} ioperm01"
      fi
      # Bug 1932436 - avc denied related to sssd and systemd-hostname
      rlRun "make -f /usr/share/selinux/devel/Makefile sssd-mod.pp" 0 "Building sssd SELinux module"
      rlRun "make -f /usr/share/selinux/devel/Makefile systemd-hostnam-mod.pp" 0 "Building systemd-hostname SELinux module"
      rules="${rules} sssd-mod systemd-hostnam-mod"
      # Fedora 33 doesn't have lockdown class
# Temporarily enable avc for 1933680 to be able to provide more info in the BZ
#      if seinfo --class lockdown -x  | grep -q confidentiality ; then
#          # Bug 1933680 - avc: denied { confidentiality } for pid=814 comm="modprobe" lockdown_reason="use of tracefs"
#          rlRun "make -f /usr/share/selinux/devel/Makefile modprobe-mod.pp" 0 "Building modprobe SELinux module"
#          rules="${rules} modprobe-mod"
#      fi
      for rule in $rules; do
           rlRun "semodule -i ${rule}.pp"  0 "Installing $rule SELinux modules"
      done
    elif ! grep "ipv6.disable=1" /proc/cmdline ; then
      rlLog "No custom SELinux modules required, skipping"
      rstrnt-report-result $TEST SKIP
      exit
    fi
  rlPhaseEnd
rlJournalPrintText
rlJournalEnd
