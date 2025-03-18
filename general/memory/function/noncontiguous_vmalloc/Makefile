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
