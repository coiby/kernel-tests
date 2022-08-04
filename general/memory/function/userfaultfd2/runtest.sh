#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/memory/function/userfaultfd2
#   Description: Kernel self test for userfaultfd mechanism
#   Author: David McDougall <dmcdouga@redhat-com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="kernel"

if rlIsRHEL '<9' ; then
    gcc -lpthread userfaultfd-old.c -o userfaultfd
else
    gcc -lpthread userfaultfd-new.c -o userfaultfd
fi

rlJournalStart
    rlPhaseStart "FAIL" "Anonymous Memory"
        if grep -q CONFIG_HAVE_ARCH_USERFAULTFD_WP=y /boot/config-"$(uname -r)" 2>/dev/null  ; then
            rlRun "./userfaultfd anon 128 32" 0 "running userfaultfd basic test"
            # See madvise_behavior_valid in madvise.c MADV_NOHUGEPAGE will get EINVAL
            if CONFIG_TRANSPARENT_HUGEPAGE=y /boot/config-"$(uname -r)" 2>/dev/null; then
                export thp_support=1
            else
                rlLogInfo "Transparent hugepage not supported, ignore MADV_NOHUGEPAGE error in userfaultfd-new.c."
            fi
        else
            rlLogInfo "Skip anon userfaultfd test: CONFIG_HAVE_ARCH_USERFAULTFD_WP is not enabled"
        fi
    rlPhaseEnd

    rlPhaseStart "FAIL" "Shared Memory"
        rlRun "./userfaultfd shmem 128 32" 0 "running userfaultfd shmem test"
    rlPhaseEnd

    rlPhaseStart "FAIL" "Hugetlbfs"
        if rlIsRHEL '<8' ; then
            rlLogInfo "Skip hugetlbfs userfaultfd test on RHEL-7 and earlier."
        else
            cat /proc/filesystems | grep -q hugetlbfs
            if [ $? -ne 0 ]; then
                echo "hugetlbfs not found in /proc/filesystems, skipping test"
                report_result Test_Skipped PASS 99
                exit 0
            fi
            # Mount the hugetlbfs.
            mnt=./huge
            mkdir $mnt
            rlRun "mount -t hugetlbfs none $mnt"

            # get huge pagesize from /proc/meminfo
            while read name size unit; do
                if [ "$name" = "Hugepagesize:" ]; then
                    hpgsize_KB=$size
                fi
            done < /proc/meminfo

            # Reserve hugepages for testing.
            hpgsize_MB=$((hpgsize_KB / 1024))
            half_ufd_size_MB=$(((( $(nproc) * hpgsize_MB + 127) / 128) * 128))
            needpgs=$((half_ufd_size_MB * 1024 / hpgsize_KB / $(nproc) * $(nproc) * 3))
            rlRun "echo 3 > /proc/sys/vm/drop_caches"
            rlRun "echo $needpgs > /proc/sys/vm/nr_hugepages"

            nr_hugepgs=`cat /proc/sys/vm/nr_hugepages`
            if ((nr_hugepgs < needpgs )); then
                rlLogInfo "Skip hugetlbfs userfaultfd test: could not allocated enough hugepages."
            else
                # Test requires source and destination huge pages.  Size of source
                # (half_ufd_size_MB) is passed as argument to test.
                rlRun "./userfaultfd hugetlb $half_ufd_size_MB 32 $mnt/ufd_test_file" 0 "running userfaultfd hugetlb test"
            fi

            rm -f $mnt/ufd_test_file
            umount $mnt
            rm -rf $mnt
            echo 0 > /proc/sys/vm/nr_hugepages
        fi
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
