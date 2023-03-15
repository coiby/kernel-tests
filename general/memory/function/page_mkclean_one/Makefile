# The name of the package under test
TOPLEVEL_NAMESPACE=kernel
PACKAGE_NAME=general/memory/function
RELATIVE_PATH=page_mkclean_one

export TESTVERSION=1.0

export TEST=/$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

# Generated information file that describes your test
#  and test requiremnets
METADATA=

BUILT_FILES=

FILES=	$(METADATA) \
	Makefile    \
	page_mkclean_one-check.c \
	runtest.sh

run: build
	./runtest.sh

build: $(METADATA)
	test -x runtest.sh || chmod a+x runtest.sh

clean:
	rm -f *~ $(BUILT_FILES)
