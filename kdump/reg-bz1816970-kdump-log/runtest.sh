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

#  Author: Ruowen Qin   <ruqin@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1816970 - [RFE] [RHEL8] Implement debugging feature in the kexec-tools to
#                gather additional information about the kdump service failure
# Added in RHEL-8.4 kexec-tools-2.0.20-37
CheckSkipTest kexec-tools 2.0.20-37 && Report

KDUMP_STDLOGLVL=${KDUMP_STDLOGLVL:-""}
KDUMP_SYSLOGLVL=${KDUMP_SYSLOGLVL:-""}
KDUMP_KMSGLOGLVL=${KDUMP_KMSGLOGLVL:-""}

STDLOGLVL="3"
SYSLOGLVL="0"
KMSGLOGLVL="0"



ConfigKdumpLog() {
    AppendSysconfig "KDUMP_STDLOGLVL" "override" "${1}"
    AppendSysconfig "KDUMP_SYSLOGLVL" "override" "${2}"
    AppendSysconfig "KDUMP_KMSGLOGLVL" "override" "${3}"
}

ValidateSystemctlOutput() {
    # TODO add level 0 (This will be done after bz1789825 is fixed)
    Log "Start to validate kdump log output"

    Log "Save kdump log to kdump_logs file"
    journalctl --since -10s --no-pager >kdump_logs

    # Check KDUMP_STDLOGLVL
    local KDUMP_STDLOGLVL_ERR_MSG=()
    KDUMP_STDLOGLVL_ERR_MSG[3]="KDUMP_STDLOGLVL 3 expect keywords \"kdumpctl\" and \"kdump\" in journalctl output, but not found"
    KDUMP_STDLOGLVL_ERR_MSG[4]="KDUMP_STDLOGLVL 4 expect keywords \"kdumpctl\", \"kdump\",\
    	\"drivers\" and \"/sbin/kexec\" in journalctl output, but not found"
    case $STDLOGLVL in
    "0") ;;

    "1") ;;

    "2") ;;

    "3")
    	# Check the log contains kdumpctl....kdump
        grep -qE 'kdumpctl.*kdump' kdump_logs || {
            Error "${KDUMP_STDLOGLVL_ERR_MSG[3]}"
        }
        ;;
    "4")
        # Check the log contains kdumpctl.*kdump.*drivers or kdumpctl.*kdump.*/sbin/kexec
        grep -qE 'kdumpctl.*kdump.*drivers|kdumpctl.*kdump.*/sbin/kexec' kdump_logs || {
            Error "${KDUMP_STDLOGLVL_ERR_MSG[4]}"
        }
        ;;
    *)
        Error "Invalid KDUMP_STDLOGLVL '${STDLOGLVL}' for editing kdump sysconfig."
        false
        ;;
    esac

    # Check KDUMP_SYSLOGLVL
    local KDUMP_SYSLOGLVL_ERR_MSG=()
    KDUMP_SYSLOGLVL_ERR_MSG[3]="KDUMP_SYSLOGLVL 3 expect keywords \"kdump\" without \"kdumpctl\" or \"unknown\" in journalctl output, but not found"
    KDUMP_SYSLOGLVL_ERR_MSG[4]="KDUMP_SYSLOGLVL 4 expect keywords \"kdump\" \"drivers\" \"/sbin/kexec\" \
        without \"kdumpctl\" or \"unknown\" in journalctl output, but not found"
    case $SYSLOGLVL in
    "0") ;;

    "1") ;;

    "2") ;;

    "3")
        # Check the log contains kdump without key words kdumpctl and unknown
        grep 'kdump' kdump_logs | grep -qvE 'kdumpctl|unknown' || {
            Error "${KDUMP_SYSLOGLVL_ERR_MSG[3]}"
        }
        ;;
    "4")
        # Check the log contains kdump drivers and kdump.*/sbin/kexec without key words kdumpctl and unknown
        grep -E 'kdump.*drivers|kdump.*/sbin/kexec' kdump_logs | grep -qvE 'kdumpctl|unknown' || {
            Error "${KDUMP_SYSLOGLVL_ERR_MSG[4]}"
        }
        ;;
    *)
        Error "Invalid KDUMP_SYSLOGLVL  '${SYSLOGLVL}' for editing kdump sysconfig."
        false
        ;;
    esac

    # Check KDUMP_KMSGLOGLVL
    local KDUMP_KMSGLOGLVL_ERR_MSG=()
    KDUMP_KMSGLOGLVL_ERR_MSG[3]="KDUMP_KMSGLOGLVL 3 expect keywords \"unknown\" and \"kdump\" in journalctl output, but not found"
    KDUMP_KMSGLOGLVL_ERR_MSG[4]="KDUMP_KMSGLOGLVL 4 expect keywords \"unknown\", \"kdump\",\
             \"/sbin/kexec\" and \"drivers\" in journalctl output, but not found"
    case $KMSGLOGLVL in
    "0") ;;

    "1") ;;

    "2") ;;

    "3")
        # Check the log contains unknown and kdump keywords
        grep -qE 'unknown.*kdump' kdump_logs || {
            Error "${KDUMP_KMSGLOGLVL_ERR_MSG[3]}"
        }
        ;;
    "4")
        # Check the log contains unknown.*kdump with /sbin/kexec or drivers key words
        grep -qE 'unknown.*kdump.*/sbin/kexec|unknown.*kdump.*drivers' kdump_logs || {
            Error "${KDUMP_KMSGLOGLVL_ERR_MSG[4]}"
        }
        ;;
    *)
        Error "Invalid KDUMP_KMSGLOGLVL '${KMSGLOGLVL}' for editing kdump sysconfig."
        false
        ;;
    esac

    # Upload kdump_logs filename
    local filename=kdump_logs_${STDLOGLVL}${SYSLOGLVL}${KMSGLOGLVL}

    cp -f kdump_logs $filename
    Log "Log filename ${filename}"
    RhtsSubmit $filename
}

LogTest() {
    STDLOGLVL=$1
    SYSLOGLVL=$2
    KMSGLOGLVL=$3

    # Avoid mixed log output
    sleep 10
    Log "Test: Log Level KDUMP_STDLOGLVL=$STDLOGLVL KDUMP_SYSLOGLVL=$SYSLOGLVL KDUMP_KMSGLOGLVL=$KMSGLOGLVL"
    ConfigKdumpLog "$STDLOGLVL" "$SYSLOGLVL" "$KMSGLOGLVL"
    LogRun "systemctl restart kdump"
    ValidateSystemctlOutput "$STDLOGLVL" "$SYSLOGLVL" "$KMSGLOGLVL"

    Log "Test: Systemctl kdump restart validating output finished"
    # Avoid mixed log output
    sleep 5
}

KdumpLogTest() {
    # Test the info level log output in STD output
    eval MultihostStage validation LogTest "3" "0" "0"

    # Test the info level log output in syslog
    eval MultihostStage validation LogTest "0" "3" "0"

    # Test the info level log output in /dev/kmsg
    eval MultihostStage validation LogTest "0" "0" "3"

    # Test the debug level log output in std , syslong and kmsg
    eval MultihostStage validation LogTest "4" "4" "4"

    # Addtional Test if provied KDUMP_STDLOGLVL, KDUMP_SYSLOGLVL and KDUMP_KMSGLOGLVL
    if [[ -n "$KDUMP_STDLOGLVL" && -n "$KDUMP_SYSLOGLVL" && -n "$KDUMP_KMSGLOGLVL" ]]; then
        Log "Addtional Test: Log Level KDUMP_STDLOGLVL=${KDUMP_STDLOGLVL} KDUMP_SYSLOGLVL=${KDUMP_SYSLOGLVL} KDUMP_KMSGLOGLVL=${KDUMP_KMSGLOGLVL}"
        LogTest "$KDUMP_STDLOGLVL" "$KDUMP_SYSLOGLVL" "$KDUMP_KMSGLOGLVL"
        Log "Addtional Test: Systemctl kdump restart validating output finished"
    fi
}

# --- start ---
Multihost KdumpLogTest
