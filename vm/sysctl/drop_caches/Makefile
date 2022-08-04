# Copyright (c) 2011 Red Hat, Inc. All rights reserved. This copyrighted material 
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Zhouping Liu <zliu@redhat.com> 

TOPLEVEL_NAMESPACE=

PACKAGE_NAME=kernel

RELATIVE_PATH=vm/sysctl/drop_caches

export TESTVERSION=1.1

# The combined namespace of the test.
export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)


# A phony target is one that is not really the name of a file.
# It is just a name for some commands to be executed when you
# make an explicit request. There are two reasons to use a
# phony target: to avoid a conflict with a file of the same
# name, and to improve performance.
.PHONY: all install download clean

# executables to be built should be added here, they will be generated on the system under test.
BUILT_FILES= 

# data files, .c files, scripts anything needed to either compile the test and/or run it.
FILES=$(METADATA) runtest.sh Makefile PURPOSE drop_caches.sh

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x ./runtest.sh
	chmod a+x ./drop_caches.sh

clean:
	rm -f *~ *.rpm $(BUILT_FILES)

# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA): Makefile
	@touch $(METADATA)
	@echo "Owner:        Zhouping Liu <zliu@redhat.com>" > $(METADATA)
	@echo "Name:         $(TEST)" >> $(METADATA)
	@echo "Path:         $(TEST_DIR)"	>> $(METADATA)
	@echo "License:      GPLv3" >> $(METADATA)
	@echo "TestVersion:  $(TESTVERSION)"	>> $(METADATA)
	@echo "Description:  FIXME: add a description here ">> $(METADATA)
	@echo "TestTime:     10m" >> $(METADATA)
	@echo "Releases:     RHELServer5 RHEL6 RHEL7" >>$(METADATA)
	@echo "RunFor:       $(PACKAGE_NAME)" >> $(METADATA)  
	@echo "RhtsRequires:      rh-tests-kernel-vm-sysctl-include" >> $(METADATA)  
