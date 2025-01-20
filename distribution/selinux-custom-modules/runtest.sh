#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Set the full test name
# TEST variable is used by beakerlib
export TEST="/kernel/distribution/selinux-custom-modules"

rlJournalStart

  rlPhaseStartTest

    # enable selinux with full audit, usefull to submit selinux-policy bugs
    # https://lukas-vrabec.com/index.php/2018/07/16/how-to-enable-full-auditing-in-audit-daemon/
    if [[ -n "${FULL_AUDIT}" ]]; then
        rlRun "sed -i '/-a task,never/d' /etc/audit/rules.d/audit.rules"
        rlRun "echo '-w /etc/shadow -p w' >> /etc/audit/rules.d/audit.rules"
        rlServiceStart auditd
        # it looks like there is a bug with audit and -sv option doesn't work well with full audit
        rlRun "sed -i 's/ -sv no//' /usr/share/restraint/plugins/report_result.d/10_avc_check"
    fi

    # https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests/-/issues/528
    # Bug 1932849 - avc: denied { module_request } kmod="net-pf-10"
    if grep "ipv6.disable=1" /proc/cmdline ; then
      rlRun "setsebool -P domain_kernel_load_modules on" 0 "Mask problems with module_request due BZ1932849 when IPv6 is disabled"
    fi

    if rlIsFedora; then
      echo "(allow iptables_t container_file_t (dir (ioctl)))" > bz2031022.cil
      modules_to_load+=" bz2031022.cil"
      echo "(allow syslogd_t var_log_t (file (relabelfrom relabelto)))" > bz2075527.cil
      modules_to_load+=" bz2075527.cil"
    fi

    if [[ -e /run/ostree-booted ]]; then
      # bz2125034
      if rlRun "setsebool -P domain_can_mmap_files on"; then
        rlLog "Custom SELinux mask for RHIVOS set successfully"
      else
        rlLog "Error setting custom SELinux RHIVOS mask"
      fi
    fi
    if [ -f /etc/build-info ]; then
      # /etc/build-info automotive builds only
      # RHEL-56385
      echo "(allow qm_t self (capability (ipc_lock)))" > rhel56385.cil
      modules_to_load+=" rhel56385.cil"
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
      if ! [[ -e /run/ostree-booted ]]; then
        rlLog "No custom SELinux modules required, skipping"
      fi
    fi
  rlPhaseEnd
rlJournalPrintText
rlJournalEnd
