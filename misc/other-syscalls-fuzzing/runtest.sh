#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Wrapper script for remaining syscalls fuzzing test using syzkaller.
# Alongside running LTP/syscalls within the QM container.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

export TEST=other-syscalls-fuzzing

LTP_VERSION=${LTP_VERSION:-20250130}
mm_syscalls=${mm_syscalls:-'acct'}
exclude_ltp_tests=${exclude_ltp_tests:-''}
timer=${timer:-3600}

# Get and build LTP/syscalls testsuite
function setup_ltp()
{
    git clone --recurse-submodules https://gitlab.com/redhat/centos-stream/tests/ltp.git
    pushd ltp
    rlRun "git checkout $LTP_VERSION"
    rlRun "make autotools"
    rlRun "./configure"
    pushd testcases/kernel/syscalls/
    export syscalls_test_path=$(pwd)
    IFS=',' read -ra folders <<< "$(echo "${mm_syscalls//\"/}" | tr -d '\n')"
    for folder in "${folders[@]}"; do
        # Trim leading and trailing whitespace
        folder=$(echo "$folder" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        # Construct absolute path
        full_path="$syscalls_test_path/$folder"
        if [ -d "$full_path" ]; then
            rlRun "make -C $full_path"
        else
            echo "Warning: $full_path is not a directory"
        fi
    done
    popd
    popd
}

# Function to check if a file is in the excluded list
function is_excluded() {
    local file="$1"
    local basename=$(basename "$file")
    IFS=',' read -ra excluded_execs <<< "$(echo "${exclude_ltp_tests//\"/}" | tr -d '\n')"
    for excluded in "${excluded_execs[@]}"; do
        if [[ "$basename" == "$excluded" ]]; then
            return 0  # True, it is excluded
        fi
    done
    return 1  # False, it is not excluded
}

# Get syscalls in scope list, execute LTP/syscalls tests for each one.
# Parameter is run time in seconds, default is 60 seconds.
function run_ltp_syscalls_continuously()
{
    # wait for syzkaller binary to be built
    while [ ! -f ../../memory/mmra/syzkaller/syzkaller/syzkaller-test.cfg ]; do
        sleep 10
    done
    IFS=',' read -ra folders <<< "$(echo "${mm_syscalls//\"/}" | tr -d '\n')"
    deadline=$(($SECONDS+${1:-60}))
    while [ $SECONDS -lt $deadline ]; do
        for folder in "${folders[@]}"; do
            # Trim leading and trailing whitespace
            folder=$(echo "$folder" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            # Construct absolute path
            full_path="$syscalls_test_path/$folder"
            # Iterate over executables and run them in QM
            if [ -d "$full_path" ]; then
                while IFS= read -r -d '' file; do
                    if [ -x "$file" ] && ! is_excluded "$file"; then
                        echo "Executing: $file"
                        podman exec -it qm $file
                    fi
                done < <(find "$full_path" -type f -executable -print0 | sort -z)
            else
                echo "Warning: $full_path is not a directory"
            fi
        done
    done
}

rlJournalStart
    rlPhaseStartSetup
        rlRun setup_ltp
        # Setup container mountpoints
        mkdir -p /etc/containers/systemd/qm.container.d
        cat > /etc/containers/systemd/qm.container.d/ltp_syscalls.conf << EOF
[Container]
Volume=${syscalls_test_path}:${syscalls_test_path}:z
EOF
        cat /etc/containers/systemd/qm.container.d/ltp_syscalls.conf
        rlRun "systemctl daemon-reload"
        rlRun "systemctl restart qm"
    rlPhaseEnd
    rlPhaseStartTest "Run LTP syscalls tests in QM, syzkaller in ASIL-B"
        run_ltp_syscalls_continuously $timer &
        pushd ../../memory/mmra/syzkaller
        rlLog "Fuzzing syscalls in ASIL-B context"
        rlRun "bash ./runtest.sh"
        popd
        wait
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
