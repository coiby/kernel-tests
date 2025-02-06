#!/bin/bash

# Install dependencies
dnf install -y gcc clang wget unzip vim git automake libtool openssl-devel numactl-devel nasm zlib-devel pip bzip2 && pip install -y prettytable

# Get libzstd.a from source
git clone https://github.com/facebook/zstd.git
cd zstd
make -j$(nproc) && make install
cd ..

# Set kernel boot parameters
grubby --update-kernel=ALL --args="intel_iommu=on,sm_on"

# Decompress the qat_4xxx firmware and reboot
if ls /lib/firmware/qat_4*.bin.xz > /dev/null 2>&1; then
	unxz /lib/firmware/qat_4*.bin.xz
elif ls /lib/firmware/qat_4*.bin > /dev/null 2>%1; then
	echo "QAT firmware is acitive"
else
	# Download the firmware packages if they are not present on the machine
	wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_4xxx.bin
	wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qat_4xxx_mmp.bin
	mv qat_4xxx.bin /lib/firmware
	mv qat_4xxx_mmp.bin /lib/firmware
fi

# Reboot to active the firmware (Beaker safe)
rstrnt-reboot
