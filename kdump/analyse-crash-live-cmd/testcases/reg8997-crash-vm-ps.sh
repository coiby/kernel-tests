#!/bin/sh

# Copyright (C) 2024 Xiaoying Yan <yiyan@redhat.com>
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

# RHEL-9001-[RHEL 8] crash- ps and vm commands fail to show correct memory usage when a process using an anonymous shared memory created by mmap() syscall.
# This bug is fixed in RHEL-8.10 crash-8.0.4-1.el8
# RHEL-8997-The ps and vm commands fail to show correct memory usage when a process using an anonymous shared memory created by mmap() syscall.
# This bug is fixed in RHEL-9.4 crash-8.0.4-1.el9
PrepareCrash
CheckSkipTest crash 8.0.4-1 && Report

CrashTestMemUsage() {
    cat <<EOF > "crash-ps.cmd"
ps mmap_mem_anon_flag
exit
EOF
    #The program 'reg8997.c' -  creates an anonymous shared memory region of 2 GiB using mmap() syscall with "MAP_SHARED|MAP_ANONYMOUS" flag.
    rm -rf ./mmap_mem_anon_flag.c ./mmap_mem_anon_flag
    \cp testcases/reg8997.c ./mmap_mem_anon_flag.c

    Log "Build mmap_mem_anon_flag test"
    CommandExists gcc || InstallDevTools
    gcc -o mmap_mem_anon_flag ./mmap_mem_anon_flag.c
    rm ./mmap_mem_anon_flag.c

    Log "Execute mmap_mem_anon_flag"
    ./mmap_mem_anon_flag &

    LogRun "crash -i crash-ps.cmd > crash-ps.log"
    RhtsSubmit "$(pwd)/crash-ps.cmd"
    RhtsSubmit "$(pwd)/crash-ps.log"

    # crash command "ps" shows that the total RSS of the "mmap_mem_anon_flag" task
    ps_rss_value=$(tail -n 2 crash-ps.log  |head -n 1 |awk '{print $8}')
    pid_value=$(tail -n 2 crash-ps.log  |head -n 1 |awk '{print $1}')

    Log "Check if the crash command 'ps' and 'vm' show the correct memory usage"
    CheckRSSValue ${ps_rss_value}

    cat <<EOF > "crash-vm.cmd"
vm ${pid_value}
exit
EOF
    LogRun "crash -i crash-vm.cmd > crash-vm.log"
    RhtsSubmit "$(pwd)/crash-vm.cmd"
    RhtsSubmit "$(pwd)/crash-vm.log"

    # crash command "vm" shows that the total RSS of the "mmap_mem_anon_flag" task
    vm_rss_value=$(grep RSS -A 1 crash-vm.log | tail -n 1 | awk '{print $3}' | awk -F 'k' '{print $1}')
    CheckRSSValue ${vm_rss_value}

    rm -f crash-*
}

CheckRSSValue() {
    # 2097152k - 2 GB memory filled with 0 by memset()
    # mem_value= 2097152k
    local mem_value=2097152

    if [ $1 -ge ${mem_value} ]; then
         Log "The crash built-in 'ps' or 'vm' command shows correct memory usage when a process using an anonymous shared memory region created by mmap() syscall."
    else
         Error "The crash built-in 'ps' or 'vm' command fail to show correct memory usage when a process using an anonymous shared memory region created by mmap() syscall."
    fi
}

# --- start ---
Multihost CrashTestMemUsage
