
# The version of the test rpm that gets created/submitted.
export TESTVERSION=1.0

# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=/$(PACKAGE_NAME)

# The toplevel namespace within which the test lives.
PACKAGE_NAME=kernel

# The name of the package under test.
RELATIVE_PATH=include

# The relative path name to the test
export TEST=$(TOPLEVEL_NAMESPACE)/$(RELATIVE_PATH)

# Include common global make rules file
include /usr/share/rhts/lib/rhts-make.include

# All files you want bundled into your rpm:
# data files, scripts, and anything needed to either 
# compile the test and/or run it.
FILES=	$(METADATA) \
	runtest.sh 

build:	
	chmod a+x runtest.sh

run:	$(FILES) build
	./runtest.sh
	
clean:	
	$(RM) $(METADATA)
	$(RM) *~ kernel-kernel-include*

# Generate the testinfo.desc here:
$(METADATA):
	touch $(METADATA)
	@echo "Name:		$(TEST)"        >$(METADATA)
	@echo "Description:	Common functions and/or variables for Kernel Testing Tasks." >>$(METADATA)
	@echo "Path:		$(TEST_DIR)"    >>$(METADATA)
	@echo "TestTime:	5m"             >>$(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"	>>$(METADATA)
	@echo "License:		GPLv3"          >>$(METADATA)
	@echo "Owner:		Paul Bunyan<pbunyan@redhat.com>" >>$(METADATA)
	@echo "Provides:        test(/kernel/include)"           >>$(METADATA)
	@cat $(METADATA)

# EndFile
