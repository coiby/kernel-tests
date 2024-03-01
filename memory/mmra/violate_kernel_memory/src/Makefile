obj-m += violate_kernel_memory.o
DEFAULT = make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
default:
	$(DEFAULT)
clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
all:
	$(DEFAULT)
	-rmmod violate_kernel_memory
	dmesg -C
	insmod violate_kernel_memory.ko
	dmesg
test:
	-rmmod violate_kernel_memory
	dmesg -C
	insmod violate_kernel_memory.ko
	dmesg
