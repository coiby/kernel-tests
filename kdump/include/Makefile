# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2008 Red Hat, Inc. All rights reserved.
#
#   Author: CAI Qian    <caiqian@redhat.com>
#   Update: Guangze Bai <gbai@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

export TEST        := /kernel/kdump/include
export TESTVERSION := 3.0

# Common VARs from rhts makefile
export TEST_DIR=/mnt/tests$(TEST)
export METADATA=testinfo.desc

.PHONY: build clean run

# All files you want bundled into your rpm.
SCRIPT := runtest.sh lib.sh kdump.sh kdump-multi.sh crash.sh id_rsa.pub id_rsa.pri crashkernel-default.json
FILES  := $(METADATA) Makefile PURPOSE $(SCRIPT)


build:
	chmod u+x $(SCRIPT)

clean:
	rm -f $(METADATA)

run: $(FILES) build
	./runtest.sh

$(METADATA):
	touch $(METADATA)
	@echo "Name:         $(TEST)"                            > $(METADATA)
	@echo "Path:         $(TEST_DIR)"                        >>$(METADATA)
	@echo "TestVersion:  $(TESTVERSION)"                     >>$(METADATA)
	@echo "TestTime:     5m"                                 >>$(METADATA)
	@echo "License:      GPLv3"                              >>$(METADATA)
	@echo "Owner:        Kdump QE <kdump-qe-list@redhat.com>" >>$(METADATA)
	@echo "Description:  Common functions for Kdump testing" >>$(METADATA)
	@echo "Requires:	  kernel-devel elfutils-libelf-devel" >>$(METADATA)
