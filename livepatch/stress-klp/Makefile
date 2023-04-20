# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Makefile of /kernel/livepatch/stress-klp
#   Description: Kernel Livepatch stress testsuite
#   Author: Dennis Li <denli@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2022 Red Hat, Inc.
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

export TEST=/kernel/livepatch/stress-klp
export TESTVERSION=1.0

FILES=$(METADATA) runtest.sh Makefile PURPOSE

.PHONY: build clean run

build:	$(METADATA)
	chmod a+x ./runtest.sh

clean:
	rm -f $(METADATA)

run:	build
	./runtest.sh


include /usr/share/rhts/lib/rhts-make.include

$(METADATA):
	touch $(METADATA)
	@echo "Owner:           Dennis Li <denli@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     Kernel Livepatch stress testsuite based on SUSE's qa_test_klp" >> $(METADATA)
	@echo "Type:            Stress" >> $(METADATA)
	@echo "TestTime:        20m" >> $(METADATA)
	@echo "RunFor:          kernel" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2+" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)

	rhts-lint $(METADATA)
