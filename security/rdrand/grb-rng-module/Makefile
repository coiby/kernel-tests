obj-m += grb-rng.o
RHEL_VERSION=$(shell sed 's/.* release \([0-9]\).*/\1/' /etc/redhat-release)
ifeq ($(RHEL_VERSION), 5)
	EXTRA_CFLAGS := -DRHEL5
endif
ifeq ($(RHEL_VERSION), 6)
	EXTRA_CFLAGS := -DRHEL6
endif
ifeq ($(RHEL_VERSION), 7)
	EXTRA_CFLAGS := -DRHEL7
endif
ifeq ($(RHEL_VERSION), 8)
	EXTRA_CFLAGS := -DRHEL8
endif
ifeq ($(RHEL_VERSION), 9)
	EXTRA_CFLAGS := -DRHEL9
endif

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
