# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc. All rights reserved.
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

export TEST  :=   /kernel/kdump/reg-bz2170851-crash-net

# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

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
	@echo "Description: Regression Test for bug 2170851" >> $(METADATA)
	rhts-lint $(METADATA)
