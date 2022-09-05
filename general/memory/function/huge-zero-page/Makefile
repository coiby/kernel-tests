#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
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
#   Author: Li Wang <liwang@redhat.com>

# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=

# The name of the package under test:
PACKAGE_NAME=kernel

# The path of the test below the package:
RELATIVE_PATH=general/memory/function/huge-zero-page

# Version of the Test. Used with make tag.
export TESTVERSION=1.0

# The combined namespace of the test.
export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

.PHONY: all install download clean

# executables to be built should be added here, they will be generated on the system under test.
BUILT_FILES=test_memcmp

# data files, .c files, scripts anything needed to either compile the test and/or run it.
FILES=$(METADATA) Makefile PURPOSE test_memcmp.c test_huge_zero_page.sh

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	test -x runtest.sh || chmod a+x runtest.sh

clean:
	rm -f *~ $(BUILT_FILES)

# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA): Makefile
	@echo "Owner:           Li Wang <liwang@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     Test case for Huge Zero Page" >> $(METADATA)
	@echo "TestTime:        1m" >> $(METADATA)
	@echo "Bug:             1035927" >> $(METADATA)
	@echo "RunFor:          $(PACKAGE_NAME)" >> $(METADATA)
	@echo "Requires:        " >> $(METADATA)
	@echo "Releases:        RedHatEnterpriseLinuxServer6 RedHatEnterpriseLinuxServer7" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
	
	rhts-lint $(METADATA)
