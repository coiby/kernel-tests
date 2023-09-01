#!/bin/sh

# Copyright (C) 2015 Red Hat

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Author Qiao Zhao <qzhao@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh


TriggerHungTaskPanic()
{
    Log "Enable kernel.hung_task_panic"
    sysctl -w kernel.hung_task_panic=1

    which gcc > /dev/null 2>&1 || InstallDevTools

    Log "Make and install hung-task module"
    rm -rf hung-task
    mkdir hung-task
    cd hung-task
    cp ../hung-task.c .
    cp ../Makefile.hung-task Makefile
    cp ../run-hung-task.c .

    unset ARCH
    make && make install || MajorError 'Make hung-task.ko module fail.'

    Log "Run hung-task"
    sync;sync;sync; sleep 10
    ./run-hung-task
    export ARCH=$(uname -m)
    cd ..
}


# --- start ---
Multihost SystemCrashTest TriggerHungTaskPanic
