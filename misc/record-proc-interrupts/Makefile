# Copyright (c) 2015 Red Hat, Inc. All rights reserved. This copyrighted
# material is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General Public
# License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: Jeffrey Bastian <jbastian@redhat.com>

export TEST=/kernel/misc/record-proc-interrupts
export TESTVERSION=1.0

# A phony target is one that is not really the name of a file.
# It is just a name for some commands to be executed when you
# make an explicit request. There are two reasons to use a
# phony target: to avoid a conflict with a file of the same
# name, and to improve performance.
.PHONY: all install download clean

# executables to be built should be added here, they will be generated on the system under test.
BUILT_FILES= 

# data files, .c files, scripts anything needed to either compile the test and/or run it.
FILES=$(METADATA) runtest.sh Makefile

run: build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x ./runtest.sh

clean:
	rm -f *~ *.rpm $(BUILT_FILES)

# You may need to add other targets e.g. to build executables from source code
# Add them here:


# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA): Makefile
	@touch $(METADATA)
	@echo "Owner:        Jeffrey Bastian <jbastian@redhat.com>" > $(METADATA)
	@echo "Name:         $(TEST)" >> $(METADATA)
	@echo "Path:         $(TEST_DIR)"       >> $(METADATA)
	@echo "License:      GPLv2" >> $(METADATA)
	@echo "TestVersion:  $(TESTVERSION)"    >> $(METADATA)
	@echo "Description:  record /proc/interrupts output">> $(METADATA)
	@echo "TestTime:     5m" >> $(METADATA)
	@echo "RunFor:       kernel" >> $(METADATA)
	@echo "Releases:     RHEL5 RHEL6 RHEL7" >> $(METADATA)
	@echo "Architectures: x86_64 aarch64 ppc64 ppc64le s390 s390x" >> $(METADATA)
	@echo "Destructive:  no" >> $(METADATA)
	@echo "Confidential: no" >> $(METADATA)
	@echo "Priority:     Normal" >> $(METADATA)
	@echo "RhtsRequires: beakerlib" >> $(METADATA)
	@echo "RhtsRequires: beakerlib-redhat" >> $(METADATA)
