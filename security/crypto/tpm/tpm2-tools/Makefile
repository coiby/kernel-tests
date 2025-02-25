# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=kernel

# The name of the package under test:
PACKAGE_NAME=crypto

# The path of the test below the package:
RELATIVE_PATH=tpm/tpm2-tools

# Version of the Test. Used with make tag.
export TESTVERSION=0.1

# The combined namespace of the test.
export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)


# A phony target is one that is not really the name of a file.
# It is just a name for some commands to be executed when you
# make an explicit request. There are two reasons to use a
# phony target: to avoid a conflict with a file of the same
# name, and to improve performance.
.PHONY: all install download clean

# executables to be built should be added here, they will be generated on 
# the system under test.
BUILT_FILES= 

# data files, .c files, scripts anything needed to either compile the test 
# and/or run it.
FILES=$(METADATA) runtest.sh Makefile PURPOSE

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x ./runtest.sh

clean:
	rm -f *~ *.rpm $(BUILT_FILES) 

# You may need to add other targets e.g. to build executables from source code
# Add them here:


# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA): Makefile
	@touch $(METADATA)
	@echo "Owner:        Vilem Marsik <vmarsik@redhat.com>" > $(METADATA)
	@echo "Name:         $(TEST)" >> $(METADATA)
	@echo "Path:         $(TEST_DIR)"	>> $(METADATA)
	@echo "License:      GPLv3+" >> $(METADATA)
	@echo "TestVersion:  $(TESTVERSION)"	>> $(METADATA)
	@echo "Description:  TPM2 tests">> $(METADATA)
	@echo "TestTime:     20m" >> $(METADATA)
	@echo "RunFor:       $(PACKAGE_NAME)" >> $(METADATA)  
	@echo "Requires:     $(PACKAGE_NAME) tpm2-tools tpm2-abrmd beakerlib" >> $(METADATA)  
	@echo "Releases:     RHEL7" >> $(METADATA)
# add any other requirements for the script to run here

# You may need other fields here; see the documentation
#	rhts-lint $(METADATA)
