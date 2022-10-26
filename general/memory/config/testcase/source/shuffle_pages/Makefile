PWD = $(shell pwd)
KVER ?= $(shell uname -r)
KDIR := /lib/modules/$(KVER)/build

obj-m := shuffle_pages.o
module-objs := shuffle_pages.o

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
clean:
	rm .* *.ko  *.o  *.mod.c *.order *.symvers *.mod
