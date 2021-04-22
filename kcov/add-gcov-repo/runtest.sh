#!/bin/bash

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

# Set the full test name
TEST="/kcov/add-gcov-repo"

rlJournalStart
  kernel_ver=$(uname -r | sed s/\\.`arch`//)
  repo_url="http://download.devel.redhat.com/qa/rhts/lookaside/gcov_kernels/${kernel_ver}/`arch`/"
  rlPhaseStartTest "Add kernel-gcov repo"
   rlRun "cat << EOF > /etc/yum.repos.d/kernel-gcov.repo
[kernel-gcov]
name=kernel-gcov
baseurl=${repo_url}
enabled=1
gpgcheck=0
EOF"
  rlPhaseEnd
rlJournalPrintText
rlJournalEnd
