#!/bin/sh

# Copyright (c) 2020 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#  Author: Xiaowu Wu    <xiawu@redhat.com>
#  Update: Ruowen Qin   <ruqin@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1731578 - function ftracer prevents crash kernel
# Fixed in RHEL-7.9 kernel-3.10.0-1135.el7
CheckSkipTest kernel 3.10.0-1135 && Report

TRACE_PATH=/sys/kernel/debug/tracing

ConfigTracer() {
    Log "Enable tracer"
    LogRun "echo function >$TRACE_PATH/current_tracer"
    sleep 5
    Log "Check tracer enable"
    LogRun "grep \"tracer: function\" ${TRACE_PATH}/trace" || MajorError "Cannot enable tracer"
}

# --- start ---
Multihost SystemCrashTest TriggerSysrqC ConfigTracer
