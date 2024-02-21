#!/bin/bash

. /usr/share/beakerlib/beakerlib.sh

rlJournalStart
    if stat /run/ostree-booted &>/dev/null; then
        CONFIG_FILE=/usr/lib/ostree-boot/config-$(uname -r)
    else
        CONFIG_FILE=/boot/config-$(uname -r)
    fi

    if ! grep "CONFIG_BPF_SYSCALL=y" $CONFIG_FILE; then
        rstrnt-report-result $TEST SKIP 0
        exit 0
    fi
    rlPhaseStartSetup
        if stat /run/ostree-booted &>/dev/null; then
            rpm-ostree install --apply-live --idempotent --allow-inactive -y xdp-tools
        else
            dnf install -y xdp-tools libbpf
        fi
    rlPhaseEnd
    rlPhaseStartTest "regression: RHEL-24445"
        rlRun -l "rpm -q libbpf xdp-tools"
        rlRun -l "xdp-loader status"
    rlPhaseEnd
rlJournalEnd
