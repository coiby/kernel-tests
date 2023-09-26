# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of
#   /kernel/general/scheduler/hung_task_detector
#   Description: decect hung task detector
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
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
#   Author: Chunyu Hu <chuhu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

TENV=_env
ifeq ($(PKG_TOP_DIR),)
	export PKG_TOP_DIR := $(shell p=$$PWD; while :; do \
		[ -e $$p/env.mk -o -z "$$p" ] && { echo $$p; break; }; p=$${p%/*}; done)
	export _TOP_DIR := $(shell p=$$PWD; while :; do \
		[ -d $$p/.git -o -z "$$p" ] && { echo $$p; break; }; p=$${p%/*}; done)
	-include $(PKG_TOP_DIR)/env.mk
endif
include $(TENV)
ifeq ($(_TOP_DIR),)
	_TOP_DIR=/mnt/tests/$(TOPLEVEL_NAMESPACE)
endif

export TESTVERSION=1.0

BUILT_FILES=

FILES=$(TENV) $(METADATA) runtest.sh Makefile PURPOSE kmod_hung

.PHONY: all install download clean

run: $(FILES) build
	( set +o posix; . /usr/share/beakerlib/beakerlib.sh; \
		. runtest.sh )

build: $(BUILT_FILES)
	test -x runtest.sh || chmod a+x runtest.sh

clean:
	ls

RHTS_INCLUDE=$(strip $(wildcard /usr/share/rhts/lib/rhts-make.include))
ifeq ($(RHTS_INCLUDE),)
    export TEST_DIR=/mnt/tests$(TEST)
    export METADATA=testinfo.desc
else
	include /usr/share/rhts/lib/rhts-make.include
endif

$(METADATA): Makefile
	@touch $(METADATA)
	@echo "Owner:           Chunyu Hu <chuhu@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     hung_task detect verification" >> $(METADATA)
	@echo "TestTime:        10m" >> $(METADATA)
	@echo "Releases:        RHEL6 RHEL7 RHEL8 Fedora" >> $(METADATA)
	@echo "Type:      		Function"        >> $(METADATA)
	@echo "RunFor:          kernel" >> $(METADATA)
	@echo "Requires:        gcc glibc elfutils-libelf-devel perf rsyslog stress-ng" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         RedHat Internal" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
	@echo "RhtsRequires:    kernel-kernel-general-include" >> $(METADATA)

	rhts-lint $(METADATA)

