# The name of the package under test
PACKAGE_NAME=kernel

# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=/$(PACKAGE_NAME)

# The version of the test rpm that gets
#  created / submitted
export TESTVERSION=1.2

# The path of the test below the package
RELATIVE_PATH=memory/shmget

# The relative path name to the test
export TEST=$(TOPLEVEL_NAMESPACE)/$(RELATIVE_PATH)

ifndef SYSENV
SYSENV := $(shell uname -m)
endif

# Binaries to be built
FILELIST= tshmget

# All files you want bundled into your rpm
FILES=	$(METADATA) \
	tshmget.c   \
	README      \
	runtest.sh  \
	Makefile
build:

clean:
	$(RM) *~ $(METADATA) $(FILELIST)
	$(RM) rh-tests-kernel*.rpm

run: clean build
	chmod +x ./runtest.sh
	./runtest.sh

# Include a global make rules file
include /usr/share/rhts/lib/rhts-make.include

$(METADATA):
	@touch $(METADATA)
	@echo "Owner:		Jarod Wilson <jwilson@redhat.com>" > $(METADATA)
	@echo "Name:		$(TEST)"	>> $(METADATA)
	@echo "Description:	32-bit app on 64-bit host shmget 2GB+ test by J. Marchand" >> $(METADATA)
	@echo "Path:		$(TEST_DIR)"	>> $(METADATA)
	@echo "TestTime:	10m"		>> $(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"	>> $(METADATA)
	@echo "#Releases:	All"		>> $(METADATA)
	@echo "Architectures:	x86_64 s390x"	>> $(METADATA)
	@echo "Destructive:	no"		>> $(METADATA)
	@echo "Confidential:	no"		>> $(METADATA)
	@echo "NeedProperty:	MEMORY >= 2048"	>> $(METADATA)
	@echo "Priority:	Normal"		>> $(METADATA)
	@echo "Type:		Regression"	>> $(METADATA)
	@echo "Requires:	kernel-devel"	>> $(METADATA)
	@echo "Requires:	glibc-devel gcc"	>> $(METADATA)
	@echo "Requires:	glibc-devel.i386" >> $(METADATA)
	@echo "Requires:	glibc-devel.i686" >> $(METADATA)
	@echo "Requires:	glibc-devel.s390" >> $(METADATA)
	@echo "Requires:	libgcc.i386"	>> $(METADATA)
	@echo "Requires:	libgcc.i686"	>> $(METADATA)
	@echo "Requires:	libgcc.s390"	>> $(METADATA)
	@echo "Requires:	@developer-tools" >> $(METADATA)
	@echo "RunFor:		kernel"		>> $(METADATA)
	@echo "Type:		KernelTier2"	>> $(METADATA)
	@echo "License:		GPL"		>> $(METADATA)
