#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Set the full test name
TEST="/kernel/distribution/selinux-custom-modules"

rlJournalStart

  rlPhaseStartTest
    # https://gitlab.com/cki-project/kernel-tests/-/issues/528
    # Bug 1932849 - avc: denied { module_request } kmod="net-pf-10"
    if grep "ipv6.disable=1" /proc/cmdline ; then
      rlRun "setsebool -P domain_kernel_load_modules on" 0 "Mask problems with module_request due BZ1932849 when IPv6 is disabled"
    fi

    if rlIsRHEL 9; then
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
      modules_to_load+=" rpcbind-mod.pp rhsmcertd-worke.pp rhsmcertd-worke-nodebind.pp systemd-logind-mod.pp groupadd.pp mandb-mod.pp fowner-sadc.pp"
      # Bug 1929329 - [RHEL-9] avc: denied { watch } for pid=328374 comm="avahi-daemon"
      rlRun "make -f /usr/share/selinux/devel/Makefile avahi-daemon.pp" 0 "Building avahi-daemon SELinux module"
      modules_to_load+=" avahi-daemon.pp"

      # Bug 1932436 - avc denied related to sssd and systemd-hostname
      rlRun "make -f /usr/share/selinux/devel/Makefile sssd-mod.pp" 0 "Building sssd SELinux module"
      rlRun "make -f /usr/share/selinux/devel/Makefile systemd-hostnam-mod.pp" 0 "Building systemd-hostname SELinux module"
      modules_to_load+=" sssd-mod.pp systemd-hostnam-mod.pp"
      echo "(allow domain dma_device_t (dir (getattr search open read)))" > bz1969323.cil
      modules_to_load+=" bz1969323.cil"
      echo "(allow domain init_t (dir (getattr search open read)))" > bz1965412.cil
      modules_to_load+=" bz1965412.cil"
    elif rlIsFedora; then
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
      modules_to_load+=" rpcbind-mod.pp rhsmcertd-worke.pp rhsmcertd-worke-nodebind.pp systemd-logind-mod.pp groupadd.pp mandb-mod.pp fowner-sadc.pp"
      # Skip if watch* permissions still not available, like Fedora 33
      if seinfo --common file -x | grep -q watch ; then
          # Bug 1929329 - [RHEL-9] avc: denied { watch } for pid=328374 comm="avahi-daemon"
          rlRun "make -f /usr/share/selinux/devel/Makefile avahi-daemon.pp" 0 "Building avahi-daemon SELinux module"
          modules_to_load+=" avahi-daemon.pp"
      fi
      # Bug 1932436 - avc denied related to sssd and systemd-hostname
      rlRun "make -f /usr/share/selinux/devel/Makefile sssd-mod.pp" 0 "Building sssd SELinux module"
      rlRun "make -f /usr/share/selinux/devel/Makefile systemd-hostnam-mod.pp" 0 "Building systemd-hostname SELinux module"
      modules_to_load+=" sssd-mod.pp systemd-hostnam-mod.pp"
      # Fedora34 BZ#1965743 - systemd was denied reading and searching /dev/dma_heap
      if seinfo --type | grep dma_device_t ; then
          echo "(allow domain dma_device_t (dir (getattr search open read)))" > bz1965743.cil
          modules_to_load+=" bz1965743.cil"
      fi
      # dma_device_dir_t was added in attempt to fix bz1965743, but this fix has since been reverted on Rawhide, but still present on F34
      if seinfo --type | grep dma_device_dir_t ; then
          echo "(allow domain dma_device_dir_t (dir (getattr search open read)))" > bz1971517.cil
          modules_to_load+=" bz1971517.cil"
      fi
      if seinfo --type | grep udev_var_run_t && seinfo --type | grep systemd_gpt_generator_t ; then
          echo "(allow systemd_gpt_generator_t udev_var_run_t (file (getattr open read ioctl lock)))" > bz1975125.cil
          modules_to_load+=" bz1975125.cil"
      fi

      echo "(allow systemd_modules_load_t systemd_modules_load_t (lockdown (confidentiality)))" > bz1969985.cil
      modules_to_load+=" bz1969985.cil"

      echo "(allow systemd_coredump_t usermodehelper_t (file (write)))" > bz1982961.cil
      modules_to_load+=" bz1982961.cil"

      echo "(allow groupadd_t groupadd_t (capability (setgid)))" > bz2022690.cil
      echo "(allow useradd_t useradd_t (capability (setgid)))" >> bz2022690.cil
      modules_to_load+=" bz2022690.cil"
      rlRun "make -f /usr/share/selinux/devel/Makefile bz2031356.pp" 0 "Building SELinux module for bz2031356"
      modules_to_load+=" bz2031356.pp"
      echo "(allow iptables_t container_file_t (dir (ioctl)))" > bz2031022.cil
      modules_to_load+=" bz2031022.cil"
      echo "(allow systemd_logind_t session_dbusd_tmp_t (sock_file (unlink)))" >> bz2039671.cil
      modules_to_load+=" bz2039671.cil"

      # BZ2051417 - avc denials related to scontext=system_u:system_r:NetworkManager_dispatcher_t:s
      rlRun "semanage permissive -a NetworkManager_dispatcher_t"
    fi

    if [ -n "$modules_to_load" ]; then
      if ! rlRun "semodule $(for m in $modules_to_load; do echo -n "-i $m "; done)" 0 \
          "Install required SELinux modules"; then
        rlLog "Transaction failed, trying to install modules one by one..."
        for m in $modules_to_load; do
          rlRun "semodule -i $m" 0 "Install $m SELinux module"
        done
      fi
    elif ! grep "ipv6.disable=1" /proc/cmdline ; then
      rlLog "No custom SELinux modules required, skipping"
      rstrnt-report-result $TEST SKIP
      exit
    fi
  rlPhaseEnd
rlJournalPrintText
rlJournalEnd
