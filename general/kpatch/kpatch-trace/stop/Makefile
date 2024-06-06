# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# Authors: Joe Lawrence <joe.lawrence@redhat.com>
#	   Yulia Kopkova <ykopkova@redhat.com>

# The combined namespace of the test.
export TEST=/kernel/general/kpatch-trace/stop
export TESTVERSION=1.0


# A phony target is one that is not really the name of a file.
# It is just a name for some commands to be executed when you
# make an explicit request. There are two reasons to use a
# phony target: to avoid a conflict with a file of the same
# name, and to improve performance.
.PHONY: all install download clean

# executables to be built should be added here, they will be generated on the system under test.
BUILT_FILES=

# data files, .c files, scripts anything needed to either compile the test and/or run it.
FILES=$(METADATA) runtest.sh Makefile PURPOSE

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	test -x runtest.sh || chmod a+x runtest.sh

clean:
	rm -f *~ *.rpm $(BUILT_FILES)

# You may need to add other targets e.g. to build executables from source code
# Add them here:


# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA): Makefile
	@touch $(METADATA)
	@echo "Owner:        Yulia Kopkova <ykopkova@redhat.com>" > $(METADATA)
	@echo "Name:         $(TEST)" >> $(METADATA)
	@echo "Path:         $(TEST_DIR)" >> $(METADATA)
	@echo "License:      GPLv2" >> $(METADATA)
	@echo "TestVersion:  $(TESTVERSION)" >> $(METADATA)
	@echo "Description:  Disable kpatch-patch functions tracing and collect stats">> $(METADATA)
	@echo "TestTime:     5m" >> $(METADATA)
	@echo "RunFor:       kpatch" >> $(METADATA)
	@echo "Requires:     kernel kpatch " >> $(METADATA)
	@echo "Requires:     beakerlib beakerlib-redhat" >> $(METADATA)
	@echo "Releases:     RHEL7 RedHatEnterpriseLinux8" >> $(METADATA)
