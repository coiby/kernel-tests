# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
#
#   Author: Xiaowu wu    <xiawu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

export TEST        := /kernel/kdump/config-network-bridging
export TESTVERSION := 1.0

# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

.PHONY: build clean run

# All files you want bundled into your rpm.
FILES := $(METADATA) runtest.sh Makefile PURPOSE

build:
	chmod a+x ./runtest.sh

clean:
	rm -f $(METADATA)

run: $(FILES) build
	./runtest.sh

$(METADATA):
	touch $(METADATA)
	@echo "Name:         $(TEST)"                            > $(METADATA)
	@echo "Path:         $(TEST_DIR)"                        >>$(METADATA)
	@echo "TestVersion:  $(TESTVERSION)"                     >>$(METADATA)
	@echo "TestTime:     10m"                                >>$(METADATA)
	@echo "Requires:     kexec-tools"                        >>$(METADATA)
	@echo "License:      GPLv3"                              >>$(METADATA)
	@echo "Owner:		 Kdump QE <kdump-qe-list@redhat.com>" >>$(METADATA)
	@echo "RepoRequires:    kdump/include" >> $(METADATA)
	@echo "Description:  Configure bridging network"          >>$(METADATA)
