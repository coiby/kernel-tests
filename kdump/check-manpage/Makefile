# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Copyright (c) 2023 Red Hat, Inc. All rights reserved.
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
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

export TEST  :=   /kernel/kdump/check-manpage


# Common VARs from rhts makefile
export TEST_DIR=/mnt/tests$(TEST)
export METADATA=testinfo.desc

.PHONY: build run

run: runtest.sh Makefile build
	./runtest.sh

build:
	chmod a+x ./runtest.sh

$(METADATA): Makefile
	@touch $(METADATA)
	@echo "Owner: Kdump QE <kdump-qe-list@redhat.com>" > $(METADATA)
	@echo "Name: $(TEST)" >> $(METADATA)
	@echo "Path: $(TEST_DIR)" >> $(METADATA)
	@echo "TestTime: 30m" >> $(METADATA)
	@echo "Requires: crash" >> $(METADATA)
	@echo "License: GPLv3" >> $(METADATA)
	@echo "RepoRequires:  kdump/include" >> $(METADATA)
	@echo "Description: Check the manpage for kdump related commands" >> $(METADATA)
	
