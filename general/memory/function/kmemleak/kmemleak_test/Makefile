PWD = $(shell pwd)
KVER ?= $(shell uname -r)
KDIR := /lib/modules/$(KVER)/build

obj-m := kmemleak_test.o
module-objs := kmemleak_test.o

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	rm *.ko  *.o  *.mod.c *.order *.symvers
