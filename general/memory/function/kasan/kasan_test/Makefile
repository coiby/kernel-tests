PWD = $(shell pwd)
KVER ?= $(shell uname -r)
KDIR := /lib/modules/$(KVER)/build

obj-m := kasan_test.o
module-objs := kasan_test.o

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	rm *.ko  *.o  *.mod.c *.order *.symvers
