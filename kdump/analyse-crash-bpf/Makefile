# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2019 Red Hat, Inc. All rights reserved.
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

export TEST=/kernel/kdump/analyse-crash-bpf
export TESTVERSION=1.0


# Common VARs from rhts makefile
export TEST_DIR=/mnt/tests$(TEST)
export METADATA=testinfo.desc

.PHONY: build clean run

# All files you want bundled into your rpm.
FILES := $(METADATA) runtest.sh Makefile PURPOSE testcases

build:
	chmod a+x runtest.sh

clean:
	rm -f $(METADATA)

run: $(FILES) build
	./runtest.sh

$(METADATA): Makefile
	@echo "Owner:           Kdump QE <kdump-qe-list@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     Crash bpf cmd providing information of BPF programs and maps" >> $(METADATA)
	@echo "TestTime:	    300m" >>$(METADATA)
	@echo "RunFor:          crash" >> $(METADATA)
	@echo "Requires:        crash kernel-debuginfo" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv3" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
	@echo "RepoRequires:    kdump/include" >> $(METADATA)

	
