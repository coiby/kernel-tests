#!/bin/sh

. ../include/runtest.sh

cgroup_exec hello cpu ./start.sh
