BUILT_FILES=

FILES=$(METADATA) runtest.sh Makefile PURPOSE threaded_getrandom.c threaded_getrandom_ns.c

.PHONY: all install download clean

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	test -x runtest.sh || chmod a+x runtest.sh

	
clean:
	rm -f *~ $(BUILT_FILES)