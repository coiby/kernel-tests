obj-m += stackman.o
stackman-y := main.o stacklib.o
CFLAGS=-O0

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
