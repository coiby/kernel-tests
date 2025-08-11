#!/bin/sh

# Copyright (c) 2011 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Zhouping Liu <zliu@redhat.com>
. ../include/runtest.sh || . /mnt/tests/kernel/vm/sysctl/include/runtest.sh || exit 1

TMP_FILE=`mktemp /tmp/drop_XXXXXX`
TUNE_FILE=/proc/sys/vm/drop_caches

free_pagecache()
{
    sync

    dd if=/dev/zero of="${TMP_FILE}" bs=1024k count=100 > /dev/null
    sleep 1
    original_cache=`vmstat | awk '{print $6}'| sed -n '3p'`

    dmesg -C
    echo 1 > "${TUNE_FILE}"
    verify_tune_value "${TUNE_FILE}" 1

    sleep 1
    new_pagecache=`vmstat | awk '{print $6}'| sed -n '3p'`
    if [ ${new_pagecache} -gt ${original_cache} ]; then
        echo "TestError: Can't free pagecache"
        exit 1
    fi

    rm -rf "${TMP_FILE}"
}

free_dentries_inodes()
{
    sync

    for X in `seq 1 20000`; do
        touch "${TMP_FILE}""$X"
        echo "TEST" > "${TMP_FILE}""$X"
    done
    sleep 2
    original_cache=`vmstat | awk '{print $6}'| sed -n '3p'`

    dmesg -C
    echo 2 > "${TUNE_FILE}"
    verify_tune_value "${TUNE_FILE}" 2
    sleep 2

    new_cache=$(vmstat | awk '{print $6}'| sed -n '3p')
    if [ ${new_cache} -gt ${original_cache} ]; then
        echo "TestError: Can't free dentries and inodes"
        exit 1
    fi

    rm -rf "${TMP_FILE}"*
}

free_pagecache_dentries_inodes()
{
    sync

    dd if=/dev/zero of="${TMP_FILE}" bs=1024k count=10 > /dev/null
    for X in `seq 1 100`; do
        touch "${TMP_FILE}""$X"
        echo "TEST" > "${TMP_FILE}""$X"
    done
    sleep 2

    original_cache=$(vmstat | awk '{print $6}'| sed -n '3p')

    dmesg -C
    sync
    echo 3 > "${TUNE_FILE}"
    verify_tune_value "${TUNE_FILE}" 3
    sleep 1

    new_cache=$(vmstat | awk '{print $6}'| sed -n '3p')
    if [ ${new_cache} -gt ${original_cache} ]; then
        echo "TestError: Can't free dentries and inodes and pagecache"
        exit 1
    fi

    rm -rf "${TMP_FILE}"*
}

disable_drop_caches()
{
    sync

    dmesg -C
    echo 4 > "${TUNE_FILE}"
    verify_tune_value "${TUNE_FILE}" 4
}

main()
{
    check_file_exist "${TUNE_FILE}"

    free_pagecache
    free_dentries_inodes
    free_pagecache_dentries_inodes
    disable_drop_caches

    echo "TestPASS: ${TUNE_FILE} PASS"
}

main
