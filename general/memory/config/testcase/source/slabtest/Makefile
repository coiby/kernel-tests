PWD = $(shell pwd)
KVER ?= $(shell uname -r)
KDIR := /lib/modules/$(KVER)/build

obj-m := slabtest.o
module-objs := slabtest.o

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules


clean:
	rm *.ko  *.o  *.mod.c *.order *.symvers
