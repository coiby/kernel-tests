# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/general/memory/function/memkind
#   Description: Test memkind with upstream testsuite
#   Author: Li Wang <liwan@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc. All rights reserved.
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

TOPLEVEL_NAMESPACE=kernel
RELATIVE_PATH=general/memory/function
PACKAGE_NAME=memkind

export TESTVERSION=1.7.0
export TEST=/$(TOPLEVEL_NAMESPACE)/$(RELATIVE_PATH)/$(PACKAGE_NAME)

TARGET=$(PACKAGE_NAME)-$(TESTVERSION)
TARGET_DIR=/mnt/testarea/memkind
PATCH_DIR=patches

# System Environment, i.e., architecture
ifndef SYSENV
	SYSENV := $(shell uname -m)
endif

LOOKASIDE=$(shell echo $$LOOKASIDE)
ifeq (,$(LOOKASIDE))
	LOOKASIDE=http://download.eng.bos.redhat.com/qa/rhts/lookaside/
endif

FILES=$(METADATA) runtest.sh Makefile PURPOSE $(PATCH_DIR)

.PHONY: all install download clean extract patch build

CURRENT_ARCH=$(shell uname -m)

$(TARGET).tar.gz:
ifeq ($(CURRENT_ARCH),x86_64skip)
	@echo "------ Download Package ------"
	wget -q $(LOOKASIDE)/$(TARGET).tar.gz
endif

$(TARGET): $(TARGET).tar.gz
ifeq ($(CURRENT_ARCH),x86_64skip)
	@echo "------ Extract Package ------"
	tar xzf $(TARGET).tar.gz
endif
patch:
	@echo "------ Patch the Testsuite ------"
ifeq ($(TESTVERSION),1.1.1)
	@patch -p1 -d $(TARGET) < $(PATCH_DIR)/tests-fix-Fedora-24-build-due-to-missing-header.patch
endif
ifeq ($(TESTVERSION),1.3.0)
	@patch -p1 -d $(TARGET) < $(PATCH_DIR)/0001-Fix-for-checking-autohbw-limits.patch
endif

build:
ifeq ($(CURRENT_ARCH),x86_64skip)
	@echo "------ Build the Testsuite ------"
	pushd $(TARGET); ./build_jemalloc.sh; ./autogen.sh; \
	./configure --prefix=$(TARGET_DIR) &> configlog.txt || cat configlog.txt; \
	popd
	make -C $(TARGET) all &> buildlog.txt || (cat buildlog.txt && false)
	make -C $(TARGET) install &> buildlog.txt || (cat buildlog.txt && false)
endif
	chmod a+x runtest.sh

testpatch: $(TARGET) patch

testfullbuild: $(TARGET) patch build

run: testfullbuild
	./runtest.sh

clean:
	rm -rf *~ $(TARGET) $(TARGET).tar.gz

include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           Li Wang <liwang@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     Test memkind with upstream testsuite" >> $(METADATA)
	@echo "TestTime:        60m" >> $(METADATA)
	@echo "RunFor:          $(PACKAGE_NAME) $(PACKAGE_NAME)-utils" >> $(METADATA)
	@echo "Requires:        @development numactl numactl-devel \
				libgcc.x86_64  glibc-devel.x86_64  glibc-static.x86_64 \
				gcc-c++ unzip libtool pytest memkind.x86_64  memkind-utils.x86_64 wget" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPL-v2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
	@echo "Architectures:	x86_64"	>> $(METADATA)

	rhts-lint $(METADATA)
