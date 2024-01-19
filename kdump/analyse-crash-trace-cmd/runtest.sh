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

# Source Kdump tests common functions.
. ../include/runtest.sh

CheckUnexpectedReboot

TESTARGS=${TESTARGS:-""}

DUMP_DIR=dump_tracing_dir
DUMP_M_DIR=${K_TESTAREA}/DUMP_M
NR_CORE=$(grep -c processor /proc/cpuinfo)
DEBUG_PATH=/sys/kernel/debug

for i in ${DUMP_DIR} ${DUMP_M_DIR}; do
    [ -d "$i" ] && rm -rf $i;
done

EnableTracer()
{
    Log "Check debugfs"
    if ! grep -q debugfs /proc/filesystems; then
        MajorError "No debugfs available"
    else
        LogRun "mount -t debugfs nodev ${DEBUG_PATH}"
    fi

    Log "Enabling tracer: wakeup"
    echo "wakeup" > ${DEBUG_PATH}/tracing/current_tracer
    Log "TRACING ENABLED:  $(cat ${DEBUG_PATH}/tracing/tracing_on)"
    Log "AVAILABLE TRACER: $(cat ${DEBUG_PATH}/tracing/available_tracers)"
    Log "CURRENT TRACER:   $(cat ${DEBUG_PATH}/tracing/current_tracer)"
    sleep 5
    LogRun "cat /sys/kernel/debug/tracing/trace"
    grep "tracer: wakeup" "${DEBUG_PATH}/tracing/trace" > /dev/null || {
        MajorError "Tracer: wakeup is not enabled"
    }
}

Analyse()
{
    PrepareCrash
    PACKAGE_NAME="crash-trace-command"
    LogRun "rpm -q $PACKAGE_NAME" || InstallPackages $PACKAGE_NAME
    rpm -q --quiet $PACKAGE_NAME || {
        Error "$PACKAGE_NAME is not installed."
        return
    }

    local tracer=trace.so

    CheckVmlinux

    [ "${TESTARGS,,}" = "loadtestonly" ] && {
        CrashExtensionLoadTest trace
        return
    }

    EnableTracer
    GetCorePath

    # Also check command output of this session
    cat <<EOF >"${K_TESTAREA}/crash.cmd"
extend ${tracer}
help trace
trace dump
ls ${DUMP_DIR}/*
trace dump -m ${DUMP_M_DIR}
ls ${DUMP_M_DIR}/*
trace show | head
trace show -f nocontext_info | head
trace show -f context_info | head
trace show -f sym_offset | head
trace show -f nosym_offset | head
trace show -f sym_addr | head
trace show -f nosym_addr | head
trace show -f nograph_print_duration | head
trace show -f graph_print_duration | head
trace show -f nograph_print_overhead | head
trace show -f graph_print_overhead | head
trace show -f graph_print_abstime | head
trace show -f nograph_print_abstime | head
trace show -f nograph_print_cpu | head
trace show -f graph_print_cpu | head
trace show -f graph_print_proc | head
trace show -f nograph_print_proc | head
trace show -f graph_print_overrun | head
trace show -f nograph_print_overrun | head
trace show -c 0 | head
EOF

    if [ ${NR_CORE} -gt 1 ]; then
        echo "trace show -c 0,$((NR_CORE-1)) | head" >> "${K_TESTAREA}/crash.cmd"
        echo "trace show -c 0-$((NR_CORE-1)) | head" >> "${K_TESTAREA}/crash.cmd"
    fi

    echo "extend -u ${tracer}" >> "${K_TESTAREA}/crash.cmd"
    echo "exit" >> "${K_TESTAREA}/crash.cmd"

    # shellcheck disable=SC2154
    CrashCommand "" "${vmlinux}" "${vmcore}"

    # unmount debug fs
    LogRun "umount ${DEBUG_PATH}"
}

#+---------------------------+
Multihost "Analyse"
