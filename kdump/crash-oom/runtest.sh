#!/bin/sh

# Copyright (C) 2017 Qiao Zhao <caiqian@redhat.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Source Kdump tests common functions.
. ../include/runtest.sh


TESTARGS=${TESTARGS:-"30"}

if [ "$K_ARCH" = "i686" ] || [ "$K_ARCH" = "i386" ]; then
    Warn "Crash-oom test cannot be run on $K_ARCH system. Terminate the test."
    Report
    exit
fi

TriggerOOM() {
    Log "Enable vm.panic_on_oom and vm.overcommit_memory"
    # Enable panic_on_oom
    sysctl -w vm.panic_on_oom=1
    # Enable vm.overcommit_memory to call oom-killer, detail in PURPOSE
    sysctl -w vm.overcommit_memory=1
    # Show MemTotal
    Log "System memory: $(grep MemTotal /proc/meminfo)"

    rm -rf ./bigmem_test.c ./bigmem
    \cp ./bigmem.c ./bigmem_test.c
    if [[ "$TESTARGS" =~ ^[0-9]+$ ]]; then
        sed -i "s/<<30/<<${TESTARGS}/" ./bigmem_test.c
    else
        Log "TESTARGS=${TESTARGS} is invalid. Test with default value (=30)."
    fi

    Log "Build bigmem test"
    which gcc > /dev/null 2>&1 || InstallDevTools
    gcc -o bigmem ./bigmem_test.c
    rm ./bigmem_test.c

    # Trigger panic_on_oom
    Log "Triggering panic_on_oom."
    sync;sync;sync; sleep 10
    ./bigmem
}

# --- start ---
Multihost SystemCrashTest TriggerOOM
