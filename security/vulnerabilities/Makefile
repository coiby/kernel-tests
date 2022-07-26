# Copyright (c) 2018 Red Hat, Inc. All rights reserved.
#
# Author: Jeff Bastian <jbastian@redhat.com>

# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=kernel

# The name of the package under test:
PACKAGE_NAME=security

# The path of the test below the package:
RELATIVE_PATH=vulnerabilities

# Version of the Test. Used with make tag.
export TESTVERSION=1.1

# The combined namespace of the test.
export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)


# A phony target is one that is not really the name of a file.
# It is just a name for some commands to be executed when you
# make an explicit request. There are two reasons to use a
# phony target: to avoid a conflict with a file of the same
# name, and to improve performance.
.PHONY: all install download clean

# executables to be built should be added here, they will be generated on the system under test.
BUILT_FILES= 

# data files, .c files, scripts anything needed to either compile the test and/or run it.
FILES=runtest.sh Makefile PURPOSE

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x ./runtest.sh

clean:
	rm -f *~ *.rpm $(BUILT_FILES)
