# The name of the package under test
TOPLEVEL_NAMESPACE=kernel
PACKAGE_NAME=general/memory/function
RELATIVE_PATH=page_mkclean_one

export TESTVERSION=1.0

export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

# Generated information file that describes your test
#  and test requiremnets
METADATA=testinfo.desc

FILES=	$(METADATA) \
	Makefile    \
	page_mkclean_one-check.c \
	runtest.sh

run: build
	./runtest.sh

build: $(METADATA)
	gcc -o page_mkclean_one-check page_mkclean_one-check.c
	chmod a+x ./runtest.sh

clean:
	rm -f page_mkclean_one-check
	rm -f *~

# You may need to add other taregts e.g. to build executables from source code
# Add them here:

# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA): Makefile
	@echo "Owner:           Jarod Wilson <jwilson@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:  Make sure page_mkclean_one works as it should. \
		Data corruption is bad, mmmkay? (bz220963)" >> $(METADATA)
	@echo "TestTime:        30m" >> $(METADATA)
	@echo "RunFor:          $(PACKAGE_NAME)" >> $(METADATA)
	@echo "Requires:	@development-tools" >> $(METADATA)
	@echo "Releases:        RedHatEnterpriseLinuxServer6 RedHatEnterpriseLinuxServer7" >> $(METADATA)
	@echo "Priority:        Normal" >> $(METADATA)
	@echo "License:         GPLv2" >> $(METADATA)
	@echo "Confidential:    no" >> $(METADATA)
	@echo "Destructive:     no" >> $(METADATA)
