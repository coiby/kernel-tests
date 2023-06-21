#!/bin/sh
auto_include=../../../automotive/include/rhivos.sh
[ -f $auto_include ] && . $auto_include

. ../include/runtest.sh

cgroup_exec hello cpu ./start.sh
