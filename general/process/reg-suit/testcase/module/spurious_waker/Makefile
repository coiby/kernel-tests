obj-m := wakeup.o
hung-objs := wakeup.o

KDIR := /usr/lib/modules/$(shell uname -r)/build
#-KDIR := /home/chuhu/Git/linux

PWD := $(shell pwd)

default:
	gcc suspend.c -o sigsuspend
	make -C $(KDIR) M=$(PWD) modules

clean:
	make -C $(KDIR) M=$(PWD) clean
	rm sigsuspend
