# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/general/memory/function/damon
#   Description: DAMON: Data Access MONitor verification
#   Author: Ping Fang <pifang@redhat-com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
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

TOPLEVEL_NAMESPACE=kernel
RELATIVE_PATH=general/memory/function
PACKAGE_NAME=damon

export TEST=/$(TOPLEVEL_NAMESPACE)/$(RELATIVE_PATH)/$(PACKAGE_NAME)
export TESTVERSION=1.0

TARGET=$(PACKAGE_NAME)-$(TESTVERSION)
TARGET_DIR=/mnt/testarea/damon

BUILT_FILES=
FILES=$(METADATA) runtest.sh Makefile main.fmf

.PHONY: all clean build

run: $(FILES) build
	( set +o posix; . /usr/bin/rhts_environment.sh; \
		. /usr/share/beakerlib/beakerlib.sh; \
		. runtest.sh )

build: $(BUILT_FILES)
	test -x runtest.sh || chmod a+x runtest.sh

clean:
	rm -fr *~ $(BUILT_FILES)
	sh -c "unset ARCH; cd sme_module; make clean"


include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           Ping Fang <pifang@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     DAMON verification" >> $(METADATA)
	@echo "Type:            Function" >> $(METADATA)
	@echo "TestTime:        20m" >> $(METADATA)
	@echo "RunFor:          kernel" >> $(METADATA)
	@echo "Requires:        gcc make python3 perf" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
	rhts-lint $(METADATA)

