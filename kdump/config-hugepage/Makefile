# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc. All rights reserved.
#
#   Author: WU Xiaowu    <xiawu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

export TEST        := /kernel/kdump/config-hugepage
export TESTVERSION := 1.0


# Common VARs from rhts makefile
export TEST_DIR=/mnt/tests$(TEST)
export METADATA=testinfo.desc

.PHONY: build clean run

FILES := $(METADATA) Makefile PURPOSE runtest.sh hugepage-mmap.c

build:
	chmod a+x ./runtest.sh

clean:
	rm -f $(METADATA)

run: $(FILES) build
	./runtest.sh

$(METADATA): Makefile
	touch $(METADATA)
	@echo "Name:           $(TEST)"                          > $(METADATA)
	@echo "TestVersion:    $(TESTVERSION)"	                >> $(METADATA)
	@echo "Path:           $(TEST_DIR)"                     >> $(METADATA)
	@echo "TestTime:       60m"                             >> $(METADATA)
	@echo "License:        GPLv3"                           >> $(METADATA)
	@echo "Owner:          Kdump QE <kdump-qe-list@redhat.com>" >>$(METADATA)
	@echo "RepoRequires:   kdump/include" >> $(METADATA)
	@echo "Description:    Enable and write data to hugepage"  >> $(METADATA)
