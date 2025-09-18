# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc. All rights reserved.
#
#   Author: Coiby Xu     <coxu@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

export TEST        := /kernel/kdump/config-luks-clevis-tang
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
	@echo "Name:          $(TEST)"                          >  $(METADATA)
	@echo "TestVersion:   $(TESTVERSION)"	                >> $(METADATA)
	@echo "Path:          $(TEST_DIR)"                      >> $(METADATA)
	@echo "Description:   Set up LUKS-encrypted volumes"    >> $(METADATA)
	@echo "TestTime:      10m"                              >> $(METADATA)
	@echo "License:       GPLv3"                            >> $(METADATA)
	@echo "Requires:      clevis-luks clevis-dracut tang lvm2 cryptsetup"   >> $(METADATA)
	@echo "Owner:         Kdump QE <kdump-qe-list@redhat.com>" >>$(METADATA)
