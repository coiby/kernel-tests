# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=/kernel

# The name of the package under test.
PACKAGE_NAME=kdump

# The test case name.
TEST_CASE=crash-warn

# The version of the test rpm that gets created / submitted.
export TESTVERSION=1.0

# The relative path name to the test.
export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(TEST_CASE)

# Common VARs from rhts makefile
export TEST_DIR=/mnt/tests$(TEST)
export METADATA=testinfo.desc


.PHONY: build clean run

# All files you want bundled into your rpm.
FILES= $(METADATA) runtest.sh Makefile crash-warn.c Makefile.crash-warn PURPOSE

build:	$(METADATA)
	chmod a+x ./runtest.sh

clean:
	rm -f $(METADATA)

run:	build
	./runtest.sh

$(METADATA):
	touch $(METADATA)
	@echo "Name:		$(TEST)" >$(METADATA)
	@echo "Description:	Test kdump by crashing kernel using panic_on_warn." >>$(METADATA)
	@echo "Path:		$(TEST_DIR)" >>$(METADATA)
	@echo "TestTime:	2h" >>$(METADATA)
	@echo "TestVersion:	$(TESTVERSION)" >>$(METADATA)
	@echo "License:		GPLv3" >>$(METADATA)
	@echo "Owner:		  Kdump QE <kdump-qe-list@redhat.com>" >>$(METADATA)
	@echo "RepoRequires:  kdump/include" >> $(METADATA)
	@echo "Requires:	kernel-devel elfutils-libelf-devel" >>$(METADATA)
