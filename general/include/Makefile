# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile genearal/include
#	Description: helper scripts or funcs can be generally used.
#   Author: Chunyu Hu <chuhu@redhat.com>
#   Author: Kernel-General-QE <kernel-general-qe@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
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

FILES=$(TENV) $(METADATA) Makefile PURPOSE scripts patches lib.sh lib_kpatch.sh  _env runtest.sh \
	  cgexec.sh libmem.sh

.PHONY: all install download clean

run: $(FILES) build
	( set +o posix; . /usr/bin/rhts_environment.sh; \
		. /usr/share/beakerlib/beakerlib.sh; \
		)
	./runtest.sh

build: $(BUILT_FILES)
	test -d scripts && chmod a+x scripts/*.sh
	test -x lib.sh || chmod a+x lib.sh

clean:
	rm -fr *~ $(BUILT_FILES)

include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           Chunyu Hu <chuhu@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     Store of common used helper scrips and lib functions" >> $(METADATA)
	@echo "Type:            Regression" >> $(METADATA)
	@echo "TestTime:        1h" >> $(METADATA)
	@echo "RunFor:          kernel" >> $(METADATA)
	@echo "Requires:        sysstat trace-cmd gcc glibc glibc-devel libgcc wget" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
	rhts-lint $(METADATA)

