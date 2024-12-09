#!/bin/bash -e
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k

# shellcheck source=/dev/null
. /usr/share/beakerlib/beakerlib.sh || exit 1

. ../include/tmt.sh


setup_restraint() {
    declare -A restraint_repo_map=( [Fedora]=Fedora [Red Hat Enterprise Linux]=RedHatEnterpriseLinux [CentOS Stream]=CentOSStream )

    for key in "${!restraint_repo_map[@]}"; do
        if grep -qs "$key" /etc/redhat-release; then
            rlLog "Setting up restraint repository for $key"
            cat << EOF > /etc/yum.repos.d/beaker-harness.repo
[beaker-harness]
name=beaker-harness
baseurl = http://download.devel.redhat.com/beakerrepos/harness/${restraint_repo_map[$key]}\$releasever/
enabled = 1
gpgcheck = 0
EOF
            break
        fi
    done

    dnf install -y restraint
}

setup_rstrnt_sync_service() {
    cat << 'EOF' > /usr/lib/systemd/system/rstrnt-sync.service
[Unit]
Description=rstrnt-sync

[Service]
ExecStart=rstrnt-sync-set -s INIT
Type=simple
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
    systemctl daemon-reload

    # Prevent the following error
    # /usr/bin/rstrnt-sync-set: line 75: /var/lib/restraint/rstrnt_events: No such file or directory
    mkdir -p /var/lib/restraint
    systemctl enable --now rstrnt-sync.service
}

rlJournalStart
    if systemctl is-enabled -q restraintd || [ -z "${CLIENTS}" ]; then
        rlLog "restraintd is already enabled or in single-host mode, skip test."
        rlJournalEnd
        exit 0
    fi

    rlPhaseStartSetup
        rlLog "Set up restraint repository and install restraintd"
        rlRun "setup_restraint"
    rlPhaseEnd

    rlPhaseStartTest
        # rstrnt-sync will be killed after tmt finishes test.
        # keep rstrnt-sync running forever othwerise a server will keep waiting for a
        # client
        rlLog "Setting up rstrnt-sync service"
        rlRun "setup_rstrnt_sync_service"
    rlPhaseEnd

rlJournalEnd
