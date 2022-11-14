# Copyright (c) 2012 Red Hat, Inc. All rights reserved.
#
# Author: Don Zickus <dzickus@redhat.com>

# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=kernel

# The name of the package under test:
PACKAGE_NAME=audio

# Version of the Test. Used with make tag.
export TESTVERSION=1.0

# The combined namespace of the test.
export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)


# A phony target is one that is not really the name of a file.
# It is just a name for some commands to be executed when you
# make an explicit request. There are two reasons to use a
# phony target: to avoid a conflict with a file of the same
# name, and to improve performance.
.PHONY: all install download clean

# executables to be built should be added here, they will be generated on the system under test.
BUILT_FILES= 

#main test script copied from git://git.alsa-project.org/alsa.git::audio-test/fft1.py
FFT=fft1.py

# data files, .c files, scripts anything needed to either compile the test and/or run it.
FILES=$(METADATA) runtest.sh Makefile PURPOSE wav.tar.gz $(FFT)

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	tar -zxvf wav.tar.gz
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
	@echo "Owner:        Don Zickus <dzickus@redhat.com>" > $(METADATA) 
	@echo "Name:         $(TEST)" >> $(METADATA)
	@echo "Path:         $(TEST_DIR)"	>> $(METADATA)
	@echo "License:      GPLv2" >> $(METADATA)
	@echo "TestVersion:  $(TESTVERSION)"	>> $(METADATA)
	@echo "Description:  Test audio hardware ">> $(METADATA)
	@echo "TestTime:     15m" >> $(METADATA)
	@echo "RunFor:       $(PACKAGE_NAME)" >> $(METADATA)  
	@echo "Requires:     alsa-utils" >> $(METADATA)  
	@echo "Requires:     $(PACKAGE_NAME)" >> $(METADATA)  
	@echo "Releases:     RHELServer5 RHELClient5 RHEL6 RHEL7" >> $(METADATA)
# add any other requirements for the script to run here

# You may need other fields here; see the documentation
	rhts-lint $(METADATA)
