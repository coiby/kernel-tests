# SPDX-License-Identifier: GPL-2.0
#
# Copyright (C) 2022 Red Hat, Inc.
# Author: Vladis Dronov <vdronoff@gmail.com>

obj-m += test_rsa_set_key.o
test_rsa_set_key-y := test-rsa-set-key.o

all:
	make -C /lib/modules/$(shell uname -r)/build/ M=$(PWD) modules
clean:
	make -C /lib/modules/$(shell uname -r)/build/ M=$(PWD) clean
