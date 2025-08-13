# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
#
#   Author: Xiaowu Wu    <xiawu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

export TEST        := /kernel/kdump/restart-kdump
export TESTVERSION := 1.0


# Common VARs from rhts makefile
export TEST_DIR=/mnt/tests$(TEST)
export METADATA=testinfo.desc

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
	@echo "Description:  Restart kdump service"  >>$(METADATA)
