# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc. All rights reserved.
#
#   Author: CAI Qian    <caiqian@redhat.com>
#   Update: Guangze Bai <gbai@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

export TEST        := /kernel/kdump/config-script
export TESTVERSION := 1.0


# Common VARs from rhts makefile
export TEST_DIR=/mnt/tests$(TEST)
export METADATA=testinfo.desc

.PHONY: build clean run

# All files you want bundled into your rpm.
FILES := $(METADATA) runtest.sh Makefile PURPOSE gen-helper-script

build:
	chmod a+x runtest.sh
	sh gen-helper-script

clean:
	rm -f $(METADATA)

run: $(FILES) build
	./runtest.sh

$(METADATA): Makefile
	touch $(METADATA)
	@echo "Name:         $(TEST)"                            > $(METADATA)
	@echo "TestVersion:  $(TESTVERSION)"                    >> $(METADATA)
	@echo "Path:         $(TEST_DIR)"                       >> $(METADATA)
	@echo "TestTime:     10m"                               >> $(METADATA)
	@echo "License:      GPLv3"                             >> $(METADATA)
	@echo "Requires:     kexec-tools"               >> $(METADATA)
	@echo "Owner:		Kdump QE <kdump-qe-list@redhat.com>" >>$(METADATA)
	@echo "RepoRequires:    kdump/include" >> $(METADATA)
	@echo "Description:  Configure kdump_pre/kdump_post option."  >> $(METADATA)
