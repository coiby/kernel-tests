obj-m += hw.o
all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
test:
	dmesg -C
	-insmod hw.ko
	-rmmod hw.ko
	dmesg > dmesg-unsigned.log
