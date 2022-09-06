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

BUILT_FILES=
FILES=$(METADATA) runtest.sh Makefile $(SRCS)

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x ./runtest.sh

# You may need to add other taregts e.g. to build executables from source code
# Add them here:

CFLAGS= -O -g -Wall -I /usr/include/
CC=cc
DEPEND=makedepend $(CFLAGS)

# To make an executable
$(NAME_SRC): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS)

clean:
	rm -f *~ $(BUILT_FILES) $(METADATA)
