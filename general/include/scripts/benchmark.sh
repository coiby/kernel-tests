#!/bin/bash

test -f /usr/local/lib/lib64/libbenchmark.a && echo "/usr/local/lib/lib64/libbenchmark.a already installed" && return

rpm -q gcc-c++ || yum -y install gcc-c++ &>/dev/null
rpm -q cmake || yum -y install cmake &>/dev/null
rpm -q git || yum -y install git &>/dev/null

git clone --depth 1 https://gitlab.com/redhat/centos-stream/tests/kernel/core/benchmark.git
cd benchmark

cmake -E make_directory "build"
cmake -E chdir "build" cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=on -DCMAKE_BUILD_TYPE=Release ../

# or, starting with CMake 3.13, use a simpler form:
# cmake -DCMAKE_BUILD_TYPE=Release -S . -B "build"
# Build the library.

cmake --build "build" --config Release
cmake --install ./build --prefix /usr/local/lib/

test -f /usr/local/lib/lib64/libbenchmark.a && echo /usr/local/lib/lib64/libbenchmark.a installed || echo Failed


