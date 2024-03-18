ifneq ($(KERNELRELEASE),)
# kbuild part of makefile
include Kbuild

else
# regular makefile
KERNEL_VERSION ?= $(shell uname -r)
KERNEL_SRC ?= /lib/modules/$(KERNEL_VERSION)/build

.PHONY: default modules clean modules_install

default:
	$(MAKE) -C $(KERNEL_SRC) M=$$PWD

clean:
	$(MAKE) -C $(KERNEL_SRC) M=$$PWD clean

test:
	$(MAKE) -C $(KERNEL_SRC) M=$$PWD
	dmesg -C
endif
