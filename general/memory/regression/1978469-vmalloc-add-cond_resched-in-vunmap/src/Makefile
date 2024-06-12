obj-m += kvmalloc-test.o

all:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean

modules_install:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules_install

