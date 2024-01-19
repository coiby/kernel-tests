#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/general/ftrace/include
#   Description: ftrace include RPM
#   Author: Caspar Zhang <czhang@redhat.com>
#   Update: Chunyu Hu <chuhu@redhat.com>
#   Update: Qiao Zhao <qzhao@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2010 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[[ -z $ARCH ]] && ARCH=`uname -m`

T_PATH_SYS_DEBUG=/sys/kernel/debug
T_PATH_SYS_TRACE=${T_PATH_SYS_DEBUG}/tracing

T_PATH_TRACE_DIR_OPTIONS=${T_PATH_SYS_TRACE}/options
# shellcheck disable=SC2034
T_PATH_TRACE_PERCPU=${T_PATH_SYS_TRACE}/per_cpu

T_PATH_AVAIL_TRACER=${T_PATH_SYS_TRACE}/available_tracers
T_PATH_CURR_TRACER=${T_PATH_SYS_TRACE}/current_tracer
T_PATH_TRACE_TRACE=${T_PATH_SYS_TRACE}/trace
# shellcheck disable=SC2034
T_PATH_TRACE_PIPE=${T_PATH_SYS_TRACE}/trace_pipe
# shellcheck disable=SC2034
T_PATH_TRACE_ENABLED=${T_PATH_SYS_TRACE}/tracing_enabled
T_PATH_TRACE_ON=${T_PATH_SYS_TRACE}/tracing_on
# shellcheck disable=SC2034
T_PATH_TRACE_FILTER=${T_PATH_SYS_TRACE}/set_ftrace_filter
# shellcheck disable=SC2034
T_PATH_TRACE_STACK_TRACE_FILTER=${T_PATH_SYS_TRACE}/stack_trace_filter
# shellcheck disable=SC2034
T_PATH_TRACE_STACK_MAXSZ=${T_PATH_SYS_TRACE}/stack_max_size
# shellcheck disable=SC2034
T_PATH_TRACE_STACK=${T_PATH_SYS_TRACE}/stack_trace
# shellcheck disable=SC2034
T_PATH_TRACE_OPTIONS=${T_PATH_SYS_TRACE}/trace_options

# shellcheck disable=SC2034
T_PATH_AVAIL_EVENT=${T_PATH_SYS_TRACE}/available_events
T_PATH_TRACE_EVENTS=${T_PATH_SYS_TRACE}/events
T_PATH_SET_EVENT=${T_PATH_SYS_TRACE}/set_event
# shellcheck disable=SC2034
T_PATH_STACK_TRACE=/proc/sys/kernel/stack_tracer_enabled
# shellcheck disable=SC2034
T_PATH_SCSI_DISK=( /sys/block/sd?/trace/enable )

T_PATH_PROC_SYSCTL=/proc/sys/kernel

# shellcheck disable=SC2034
T_REBOOT="./FTRACE_REBOOT"
# shellcheck disable=SC2034
T_RESTORE="./FTRACE_RESTORE"

function Log() {
    echo -e "$1" | tee -a "${OUTPUTFILE}"
}


#==== Tracer ====
function CurrentTracer() {
    cat ${T_PATH_CURR_TRACER}
}

function EnableTracer() {
    echo $1 > ${T_PATH_CURR_TRACER} || return 1
}

function DisableTracer() {
    EnableTracer nop
}

#==== Event ====
function SetEvent() {
    echo $1 > ${T_PATH_SET_EVENT} || return 1
}

function UnsetEvent() {
    echo '!'"$1" > ${T_PATH_SET_EVENT} &&
    echo > ${T_PATH_TRACE_TRACE}     ||
    return 1
}

function _EnableEvent() {
    echo 1 > $1 || return 1
}

function _DisableEvent() {
    echo 0 > $1 && echo > ${T_PATH_TRACE_TRACE} || return 1
}

function EnableEvent() {
    _EnableEvent "${T_PATH_TRACE_EVENTS}/${1/://}/enable"
}

function DisableEvent() {
    _DisableEvent "${T_PATH_TRACE_EVENTS}/${1/://}/enable"
}

function SetSubsys() {
    SetEvent "$1:*"
}

function UnsetSubsys() {
    UnsetEvent "$1:*"
}

function EnableSubsys() {
    _EnableEvent "${T_PATH_TRACE_EVENTS}/$1/enable"
}

function DisableSubsys() {
    _DisableEvent "${T_PATH_TRACE_EVENTS}/$1/enable"
}

function SetAllEvents() {
    SetEvent "*:*"
}

function UnsetAllEvents() {
    UnsetEvent "*:*"
}

function EnableAllEvents() {
    _EnableEvent "${T_PATH_TRACE_EVENTS}/enable"
}

function DisableAllEvents() {
    _DisableEvent "${T_PATH_TRACE_EVENTS}/enable"
}

function UmountDebugfs() {
    set -x
    Log "- Umounting debugfs"
    if findmnt -t debugfs; then
        /bin/umount -a -f -v -t debugfs
    fi
    /bin/umount -f -v /sys/kernel/debug
    set +x
}

function MountDebugfs() {
    local cleanup_func=$1

    UmountDebugfs
    Log "- Mounting debugfs"
    if ! mount -v -t debugfs debugfs ${T_PATH_SYS_DEBUG}; then
        rstrnt-report-result "mount_debugfs" "FAIL" 1
        eval $cleanup_func
        #exit 1
    fi
}

# Deprecated
function Initialize() {
    local cleanup_func=$1

    # Stop trace-cmd daemon if it is running
    type /etc/init.d/trace-cmd >/dev/null 2>&1 && service trace-cmd stop

    MountDebugfs "$cleanup_func"
    DisableTracer
    UnsetAllEvents
}

function Teardown() {
    DisableTracer
    UnsetAllEvents
    # As Debugfs is mounted by default, we no longer need to unmount Debugfs
    # And if we unmount it, the following cases may fail on RHEL 7
    # UmountDebugfs
}

# Get the value stored in trace file.
function _GetTraceValue()
{
    local path=$1
    local target=$2
    local tpath=$path/$target
    [ ! -e $tpath ] && echo "" && return 1;
    echo "$(cat $tpath)"
}

function _ShowTraceValue()
{
    local path=$1
    local target=$2
    local tpath=$path/$target
    [ ! -e $tpath ] && echo "" && return 1;
    echo "value of $target:"
    echo "$(cat $tpath)"
}

# Get the trace status stored in tracing file.
function GetTracingStat()
{
    local path=$T_PATH_SYS_TRACE
    local target=$1
    _GetTraceValue $path $target
}

# Get the trace status stored in sysctl file
function GetTracingStatSysctl()
{
    local path=$T_PATH_PROC_SYSCTL
    local target=$1
    _GetTraceValue $path $target
}

# Show the value stored in tracing file.
function ShowTracingStat()
{
    local path=$T_PATH_SYS_TRACE
    local target=$1
    _ShowTraceValue $path $target
}

# Show the value stored in tracing sysctl file
function ShowTracingStatSysctl()
{
    local path=$T_PATH_PROC_SYSCTL
    local target=$1
    local tpath=$path/$target
    _ShowTraceValue $path $target
}

# Show the option value in tracing/options dir
function ShowTracingStatOptions()
{
    local path=$T_PATH_TRACE_DIR_OPTIONS
    local target=$1
    _ShowTraceValue $path $target
}

# Trace buffer
function EnableTraceBuffer()
{
    echo 1 > $T_PATH_TRACE_ON
}

function DisableTraceBuffer()
{
    echo 0 > $T_PATH_TRACE_ON
}

# helper function for checking supported tracing feature
function CheckTracingSupport()
{
    local type=$1
    local target=$2
    case $type in
    tracer)
        local file=$T_PATH_AVAIL_TRACER
        if [ -f $file ] && cat $file | grep -w $target; then
            return 0
        else
            return 1
        fi
        ;;
    *)
        return 0;
        ;;
    esac
}

function SkipTracingTest()
{
    local type=$1
    local target=$2
    rstrnt-report-result "Test_Skipped_${type}/$target" "SKIP"
    rlPhaseEnd
    exit 0
}
