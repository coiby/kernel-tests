# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2008 Red Hat, Inc. All rights reserved.
#
#   Author: CAI Qian    <caiqian@redhat.com>
#   Update: Guangze Bai <gbai@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

export TEST        := /kernel/kdump/setup-bare-metal
export TESTVERSION := 4.0

# Include Common Makefile
RHTS_INCLUDE=$(strip $(wildcard /usr/share/rhts/lib/rhts-make.include))
ifeq ($(RHTS_INCLUDE),)
    export TEST_DIR=/mnt/tests$(TEST)
    export METADATA=testinfo.desc
else
    include /usr/share/rhts/lib/rhts-make.include
endif

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
	@echo "TestTime:     30m"                                >>$(METADATA)
	@echo "License:      GPLv3"                              >>$(METADATA)
	@echo "Owner:		 Kdump QE <kdump-qe-list@redhat.com>" >>$(METADATA)
	@echo "RepoRequires: kdump/include"			 >>$(METADATA)
	@echo "RepoRequires: cmdline_helper"			 >>$(METADATA)
	@echo "RepoRequires: cki_lib"			 >>$(METADATA)
	@echo "Description:  Setup bare metal Kernel for Kdump." >>$(METADATA)
