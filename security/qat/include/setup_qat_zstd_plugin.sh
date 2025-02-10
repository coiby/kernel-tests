#!/bin/bash

# Get all necessary includes
git clone https://github.com/intel/qatlib.git
cd qatlib
./autogen
./configure --enable-service
make -j$(nproc)
make install
cd ..
dnf reinstall -y qatlib qatengine

# Get and run the Intel QAT configuration script
wget https://intel.github.io/quickassist/_downloads/74bdfa2cd6bb4987b51a4f550d8f26ba/qat
python3 qat --config

# Get the baseline QAT ZSTD Plugin tests
git clone https://github.com/intel/QAT-ZSTD-Plugin.git

# Get a file to test on, recommended in the QAT ZSTD Plugin repo
wget https://sun.aei.polsl.pl//~sdeor/corpus/dickens.bz2
bunzip2 dickens.bz2

# Compile
cd QAT-ZSTD-Plugin/
make test
cd ..
