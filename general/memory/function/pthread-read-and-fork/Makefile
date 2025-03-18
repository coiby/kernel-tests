# The name of the package under test
TOPLEVEL_NAMESPACE=kernel
PACKAGE_NAME=general/memory/function
RELATIVE_PATH=pthread-read-and-fork

export TESTVERSION=1.0

export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

# Generated information file that describes your test
#  and test requiremnets
METADATA=testinfo.desc

# A phony target is one that is not really the name of a file. 
#  It is just a name for some commands to be executed when you
#  make an explicit request. There are two reasons to use a 
#  phony target: to avoid a conflict with a file of the same
#  name, and to improve performance.
.PHONY:

# All files you want bundled into your rpm
FILES=	$(METADATA)     \
	runtest.sh      \
	Makefile		\
	pthread-read-and-fork.c

clean:
	rm -rf *~ $(METADATA) libhugetlbfs*src.rpm pthread-read-and-fork write-test *.o

run:
	chmod +x ./runtest.sh
	./runtest.sh
