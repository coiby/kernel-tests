export TEST=/kernel/ima-env-utils/sanity

BUILT_FILES=

FILES=$(METADATA) runtest.sh Makefile

.PHONY: all install download clean

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	test -x runtest.sh || chmod a+x runtest.sh

clean:
	rm -f *~ $(BUILT_FILES)

include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner: Linqing Lu <lilu@redhat.com>" > $(METADATA)
	@echo "Name: $(TEST)" >> $(METADATA)
	@echo "RunFor: kernel" >> $(METADATA)
	@echo "Requires: ima-evm-utils ima-evm-utils-devel openssl" >> $(METADATA)
	@echo "Priority: Normal" >> $(METADATA)

	rhts-lint $(METADATA)

