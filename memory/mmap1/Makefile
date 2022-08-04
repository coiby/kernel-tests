# Example Makefile for RHTS
# This example is geared towards a test for a specific package
# It does most of the work for you, but may require further coding

# The toplevel namespace within which the test lives.
# FIXME: You will need to change this:
TOPLEVEL_NAMESPACE=

# The name of the package under test:
# FIXME: you wil need to change this:
PACKAGE_NAME=kernel

# The path of the test below the package:
# FIXME: you wil need to change this:
RELATIVE_PATH=memory/mmap1

# Version of the Test. Used with make tag.
export TESTVERSION=1.3

# The compiled namespace of the test.
export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

.PHONY: all install download clean

NAME_SRC=mmaptst
SRCS=$(NAME_SRC).c
OBJS=$(NAME_SRC).o

BUILT_FILES=$(NAME_SRC)
FILES=$(METADATA) runtest.sh Makefile $(SRCS)

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x ./runtest.sh
	chmod a+x ./$(NAME_SRC)

# You may need to add other taregts e.g. to build executables from source code
# Add them here:

CFLAGS= -O -g -Wall -I /usr/include/
CC=cc
DEPEND=makedepend $(CFLAGS)

# To make an executable
$(NAME_SRC): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS)

# what are the source dependencies
depend:	$(SRCS)
	$(DEPEND) $(SRCS)

clean:
	rm -f *~ $(BUILT_FILES) $(METADATA)

# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA): Makefile
	@touch $(METADATA)
	@echo "Owner:		Bill Peck <bpeck@redhat.com>" > $(METADATA)
	@echo "Name:		$(TEST)"	>> $(METADATA)
	@echo "Path:		$(TEST_DIR)"	>> $(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"	>> $(METADATA)
	@echo "Description:	mmap test"	>> $(METADATA)
	@echo "TestTime:	5m"		>> $(METADATA)
	@echo "RunFor:		$(PACKAGE_NAME)" >> $(METADATA)
	@echo "Requires:	gcc glibc bzip2" >> $(METADATA)
	@echo "Releases:	-RHEL2.1"	>> $(METADATA)
	@echo "#Architectures:	All"		>> $(METADATA)
	@echo "Priority:        Normal"		>> $(METADATA)
	@echo "Type:            Regression"	>> $(METADATA)
	@echo "License:		GPL"		>> $(METADATA)
