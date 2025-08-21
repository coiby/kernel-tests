#!/bin/sh
. ../../../cki_lib/libcki.sh || exit 1

. ../include/runtest.sh

cgroup_exec hello cpu ./start.sh
