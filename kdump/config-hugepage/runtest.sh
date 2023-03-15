#!/bin/sh

# Copyright (C) 2008 CAI Qian <caiqian@redhat.com>
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

#+---------------------------+

CheckUnexpectedReboot
which gcc || InstallDevTools

ConfigHugepage() {

    # Print mem info
    cat /proc/meminfo


    # Enable hugepage
    local default_nr_hugepages=8196
    sysctl -w vm.nr_hugepages=${default_nr_hugepages}

    hugepage_size=$(cat /proc/meminfo  | grep -i ^Hugepagesize | awk '{print $2}')
    hugepage_size_unit=$(cat /proc/meminfo  | grep -i ^Hugepagesize | awk '{print $3}')
    hugepage_size_unit=${hugepage_size_unit,,}

    cat /proc/meminfo  | grep -i ^HugePage

    # Write data to hugepage
    [ -d "huge" ] && {
        umount ./huge
        rm -rf ./huge
    }
    mkdir ./huge
    mount -t hugetlbfs none ./huge
    [ -f "hugepage-mmap" ] && \rm -f hugepage-mmap
    gcc -Wall -o hugepage-mmap hugepage-mmap.c
    ./hugepage-mmap

    # Print HugePages usages after writing data to hugepage
    cat /proc/meminfo  | grep -i ^HugePage

}

# --- start ---
Multihost "ConfigHugepage"

