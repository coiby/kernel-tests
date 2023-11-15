# Copyright (c) 2018 Red Hat, Inc. All rights reserved. This copyrighted
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
# Author: Li Wang <liwang@redhat.com>

TOPLEVEL_NAMESPACE=kernel
PACKAGE_NAME=general/memory/function
RELATIVE_PATH=pg-table_tests

export TESTVERSION=1.0
export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

# All files you want bundled into your rpm
FILES=	$(METADATA) runtest.sh Makefile heap.c mmap+memset+fork.c PURPOSE

.PHONY: clean run

clean:
	rm -f heap mmap+memset+fork *~ $(METADATA)

run:
	chmod +x ./runtest.sh
	./runtest.sh

# Include a global make rules file
include /usr/share/rhts/lib/rhts-make.include

$(METADATA):
	touch $(METADATA)
	@echo "Owner:		Li Wang <liwang@redhat.com>"		 > $(METADATA)
	@echo "Name:		$(TEST)"				>> $(METADATA)
	@echo "Description:	Verifies 5-level paging feature"	>> $(METADATA)
	@echo "Path:		$(TEST_DIR)"				>> $(METADATA)
	@echo "TestTime:	30m"					>> $(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"				>> $(METADATA)
	@echo "Releases:	RHEL8"					>> $(METADATA)
	@echo "Architectures:	x86_64"					>> $(METADATA)
	@echo "Destructive:	no"					>> $(METADATA)
	@echo "Confidential:	no"					>> $(METADATA)
	@echo "Priority:	Normal"					>> $(METADATA)
	@echo "RunFor:		kernel"					>> $(METADATA)
	@echo "License:		GPLv2"					>> $(METADATA)
	@echo "Requires:	$(PACKAGE_NAME)"			>> $(METADATA)
	@echo "Requires:	grubby gcc glibc perl vim wget numactl numactl-devel" >> $(METADATA)
