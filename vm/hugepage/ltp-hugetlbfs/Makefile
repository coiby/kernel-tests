# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/vm/hugepage/ltp-hugetlbfs
#   Description: Porting hugetlb tests from ltp to Beaker
#   Author: Caspar Zhang <czhang@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
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

include /usr/share/rhts/lib/rhts-make.include
include /mnt/tests/kernel/distribution/ltp/include/ltp-make.include

export TEST=/kernel/vm/hugepage/ltp-hugetlbfs

FILES=$(METADATA) runtest.sh Makefile PURPOSE hugetlb.inc

.PHONY: all install download clean

patch: patch-critical patch-hugetlb

build: build-basic
	$(MAKE) -C $(TARGET)/testcases/kernel/mem/hugetlb all -j1
	$(MAKE) -C $(TARGET)/testcases/kernel/mem/hugetlb install -j1
	$(MAKE) -C $(TARGET)/testcases/kernel/mem/swapping -j1

run: $(TARGET) patch build
	@echo "============ Run Tests ============"
	chmod +x ./runtest.sh
	LANG=C ./runtest.sh

$(METADATA): Makefile
	@echo "Owner:           Caspar Zhang <czhang@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     hugetlb testcases from LTP" >> $(METADATA)
	@echo "TestTime:        1h" >> $(METADATA)
	@echo "RhtsRequires:    rh-tests-kernel-distribution-ltp-include" >> $(METADATA)
	@echo "Requires:        bc gcc glibc wget automake bzip2 patch" >> $(METADATA)
	@echo "RunFor:          kernel" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
	@echo "NeedProperty:    MEMORY > 512" >> $(METADATA)
