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

TriggerWarnCrash()
{
    unset ARCH
    MakeModule 'crash-warn'
    export ARCH=$(uname -m)

    # step 1 turn on panic_on_warn
    Log "Enable panic_on_warn"
    LogRun "echo 1 > /proc/sys/kernel/panic_on_warn"

    Log "Trigger on warn crash"
    sync;sync;sync; sleep 10
    LogRun "insmod crash-warn/crash-warn.ko"
}

Multihost SystemCrashTest TriggerWarnCrash
