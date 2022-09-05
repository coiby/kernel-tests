TOPLEVEL_NAMESPACE=kernel
PACKAGE_NAME=
RELATIVE_PATH=general/memory/function/noncontiguous_vmalloc

export TESTVERSION=1.1
export TEST=/$(TOPLEVEL_NAMESPACE)/$(RELATIVE_PATH)

.PHONY: all install download clean

BUILT_FILES=

FILES=$(METADATA) runtest.sh Makefile PURPOSE module/

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x ./runtest.sh

clean:
	rm -f *~ *.rpm $(BUILT_FILES)

include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@touch $(METADATA)
	@echo "Owner:        Shizhao Chen <shichen@redhat.com>" > $(METADATA)
	@echo "Name:         $(TEST)" >> $(METADATA)
	@echo "Path:         $(TEST_DIR)"	>> $(METADATA)
	@echo "License:      GPLv3" >> $(METADATA)
	@echo "TestVersion:  $(TESTVERSION)"	>> $(METADATA)
	@echo "Description:  Non-contiguous page allocation using vmalloc()">> $(METADATA)
	@echo "TestTime:     10m" >> $(METADATA)
	@echo "RunFor:       $(PACKAGE_NAME)" >> $(METADATA)
	@echo "Requires:     @development" >> $(METADATA)
	@echo "RhtsRequires: kernel-kernel-general-include" >> $(METADATA)
