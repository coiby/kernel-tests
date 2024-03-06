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

modules:
	$(MAKE) -C $(KERNEL_SRC) M=$$PWD modules

clean:
	$(MAKE) -C $(KERNEL_SRC) M=$$PWD clean

modules_install:
	$(MAKE) -C $(KERNEL_SRC) M=$$PWD modules_install
endif
