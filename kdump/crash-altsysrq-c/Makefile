# Copyright (c) 2006 Red Hat, Inc. All rights reserved. This copyrighted material
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
# Author: WANG Chao <chaowang@redhat.com>

# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=/kernel

# The name of the package under test.
PACKAGE_NAME=kdump

# The test case name.
TEST_CASE=crash-altsysrq-c

# The version of the test rpm that gets created / submitted.
export TESTVERSION=0

# The relative path name to the test.
export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(TEST_CASE)

# Common VARs from rhts makefile
export TEST_DIR=/mnt/tests$(TEST)
export METADATA=testinfo.desc


.PHONY: build clean run

# All files you want bundled into your rpm.
FILES=	$(METADATA) runtest.sh Makefile PURPOSE altsysrq.c Makefile.altsysrq

build:	$(METADATA)
	chmod a+x ./runtest.sh

clean:
	rm -f $(METADATA)
	rm -rf altsysrq/

run:	build
	./runtest.sh

$(METADATA):
	touch $(METADATA)
	@echo "Name:		$(TEST)" >$(METADATA)
	@echo "Description:	Test Kdump by crashing Kernel via Alt+SysRq+C." >>$(METADATA)
	@echo "Path:		$(TEST_DIR)" >>$(METADATA)
	@echo "TestTime:	1h" >>$(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"	>>$(METADATA)
	@echo "License:		GPLv3" >>$(METADATA)
	@echo "Owner:         Kdump QE <kdump-qe-list@redhat.com>" >>$(METADATA)
	@echo "RepoRequires:  kdump/include" >> $(METADATA)
	@echo "Requires:	kernel-devel elfutils-libelf-devel" >>$(METADATA)

