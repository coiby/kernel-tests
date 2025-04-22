# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=/kernel

# The name of the package under test.
PACKAGE_NAME=kdump

# The name of test case.
TEST_CASE=clean-up

# The version of the test rpm that gets created / submitted.
export TESTVERSION=2.0

export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(TEST_CASE)

# Common VARs from rhts makefile
export TEST_DIR=/mnt/tests$(TEST)
export METADATA=testinfo.desc


.PHONY: build clean run

# All files you want bundled into your rpm.
FILES=	$(METADATA) runtest.sh Makefile PURPOSE

build:	$(METADATA)
	chmod a+x ./runtest.sh

clean:
	rm -f $(METADATA)

run:	build
	./runtest.sh

$(METADATA):
	touch $(METADATA)
	@echo "Name:		$(TEST)" >$(METADATA)
	@echo "Description: 	Remove all generated files from Kdump tests." >>$(METADATA)
	@echo "Path:		$(TEST_DIR)" >>$(METADATA)
	@echo "TestTime:	20m" >>$(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"	>>$(METADATA)
	@echo "License:		GPLv3" >>$(METADATA)
	@echo "Owner:		Kdump QE <kdump-qe-list@redhat.com>" >>$(METADATA)
	@echo "RepoRequires:    kdump/include" >> $(METADATA)
