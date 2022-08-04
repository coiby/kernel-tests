# SPDX-License-Identifier: GPL-2.0-or-later
# Author: Li Wang <liwang@redhat.com>

TOPLEVEL_NAMESPACE=kernel
PACKAGE_NAME=general/memory/function
RELATIVE_PATH=mm_proactive_compaction

export TESTVERSION=1.0
export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

# All files you want bundled into your rpm
FILES=	$(METADATA) \
    runtest.sh \
    mem-frag-test.c \
    Makefile \
    PURPOSE

.PHONY: clean run

clean:
	rm -f mem-frag-test buddyinfo* *~ $(METADATA)

run:
	@echo "Build mem-frag-test"
	gcc mem-frag-test.c -o mem-frag-test
	chmod +x ./runtest.sh
	./runtest.sh

# Include a global make rules file
include /usr/share/rhts/lib/rhts-make.include

$(METADATA):
	touch $(METADATA)
	@echo "Owner:		Li Wang <liwang@redhat.com>"	 	> $(METADATA)
	@echo "Name:		$(TEST)"				>> $(METADATA)
	@echo "Description:	Verifies that mm proactive_compaction works."	>> $(METADATA)
	@echo "Path:		$(TEST_DIR)"				>> $(METADATA)
	@echo "TestTime:	20m"					>> $(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"				>> $(METADATA)
	@echo "Releases:	RHEL8 RHEL9"				>> $(METADATA)
	@echo "Architectures:	x86_64 ppc64le s390x aarch64"		>> $(METADATA)
	@echo "Destructive:	no"					>> $(METADATA)
	@echo "Confidential:	no"					>> $(METADATA)
	@echo "Priority:	Normal"					>> $(METADATA)
	@echo "RunFor:		kernel"					>> $(METADATA)
	@echo "License:		GPLv2"					>> $(METADATA)
	@echo "Requires:	$(PACKAGE_NAME)"			>> $(METADATA)
	@echo "Requires:	grubby psmisc gcc glibc"		>> $(METADATA)
