obj-m = test_module_late_patching.o test_klp_late_patching.o
KERNEL_VER = $(shell uname -r)
all:
	make -C /lib/modules/$(KERNEL_VER)/build M=$(PWD) modules
clean:
	make -C /lib/modules/$(KERNEL_VER)/build M=$(PWD) clean
