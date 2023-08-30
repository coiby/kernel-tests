obj-m  := crc32c-self-check.o

UNAME := $(shell uname -m)
ifeq ($(UNAME),aarch64)
  ARCH := arm64
else ifeq ($(UNAME),ppc64)
  ARCH := powerpc
else ifeq ($(UNAME),ppc64le)
  ARCH := powerpc
else ifeq ($(UNAME),s390x)
  ARCH := s390
else ifeq ($(UNAME),x86_64)
  ARCH := x86
endif

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) ARCH=$(ARCH) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
