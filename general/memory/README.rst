Brief Introduction to Memory Testing
====================================

This directory including core-kernel memory QE team's testcases.
Each sub-directory focus on one memory feature.


function/control-the-reserved-memory
---------------------------

Testing /proc/sys/vm/admin_reserve_kbytes interface. Allow administrators to control the amount of reserved memory in the kernel.

function/gigantic-page
---------------------------

A simple tests for gigantic page allocation in rhel kernel. It will check cpu flag "pdpe1gb" which means this processor support 1GB hugepage. Then test different combination of hugepage kernel parameter. Related bugs `[1]`_ `[2]`_.

function/huge-zero-page
---------------------------

Huge zero page (hzp) is a non-movable huge page (2M on x86-64) filled with zeros. Avoid to allocate a real page on read page fault.
`HZP Reference`_

function/kasan
---------------------------

Check that Kernel-Address-Sanitizer (KASAN) is enabled.  This does a read-after-free error in the kernels memory space, and then searches "dmesg" for the resulting error message.  KASAN is currently only enabled on:
 * RHEL-8,
 * Debug kernels,
 * x86_64 & aarch64 architectures.

function/kaslr
---------------------------

Kernel Address-Space Layout Randomization, bringing support for address space randomization to running Linux kernel images by randomizing where the kernel code is placed at boot time. We reboot several times check symbol address between kaslr is enabled or not(nokaslr).

function/libhugetlbfs
--------------------------

This is for user space libhugetlbfs test. Most of the test code is copied from /kernel/vm/hugepage/libhugetlbfs, which the original test is for testing kernel thp/hugepage feature with test code from upstream libhugetlbfs repo.

function/mem_encrypt
--------------------------

This test is for AMD EPYC's memory encryption, the kernel parameter mem_encrypt=on to enable this feature. We build a module to invoke related API to encrypt and decrypt sample data.

function/memeq
--------------------------

The mem= is a kernel parameter to force usage of a specific amount of memory to be used. We try different mem= config and check system memory.

function/memfd_create
-------------------------

We use memfd_create system call to create an anonymous file and test on it.

function/memkind
-------------------------

The memkind library is a user extensible heap manager built on top of jemalloc which enables control of memory characteristics and a partitioning of the heap between kinds of memory. We just run testsuit from memkind and check the result.


function/memory-failure
------------------------

Memory failure is a kernel feature to solve issues reported by machine check handler. We use mce-inject and mce-test to generate hardware memory corruption event.

function/memsofthotplug
-------------------------

We use sysfs interface /sys/devices/system/memory to software online/offline memory block.


function/numa
-------------------------

This directory include several numa related regression testcases. and numademo to test read/write over multi node with different policy.

function/page_mkclean_one
-------------------------

Check to make sure page_mkclean_one behaves correctly.
http://bugzilla.redhat.com/220963

function/pg-table_tests
-------------------------

Test for 5-level paging.
https://github.com/sanskriti-s/pg-table_tests

function/pthread-read-and-fork
-------------------------

This is a hugetlb stress testing, parallel pthread read access and fork stress.

function/userfaultfd
-------------------------

The userfaultfd can be used for delegation of page-fault handling to a user-space application. This demonstrates the use of the userfaultfd mechanism. come from userfaultfd's manual page.

function/userfaultfd2
-------------------------

Kernel self test for userfaultfd mechanism.

function/zswap
-------------------------

Zswap is a kernel feature that provides a compressed RAM cache for swap pages. We enable zswap from kernel parameter, trigger swapout by memory stress.

.. _HZP Reference: http://lwn.net/Articles/525301
.. _[1]: https://bugzilla.redhat.com/show_bug.cgi?id=996763
.. _[2]: https://bugzilla.redhat.com/show_bug.cgi?id=1086333
