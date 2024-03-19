#!/bin/bash

# ---------------- Crash Utility related Functions ------------------------ #

# Set in GetCorePath()
export vmcore
# Set in CheckVmlinux()
export vmlinux

LsCore()
{
    LogRun 'ls -l "${vmcore}"'
    [ $? -ne 0 ] && FatalError "ls returns errors."
}

GetDumpFile()
{
    [ -z "$1" ] && return 1

    local core_dir=""
    local file_name="$1"
    dump_file_path=""

    core_dir="${K_DEFAULT_PATH}"

    [ -f "${K_PATH}" ] && core_dir="$(cat ${K_PATH})"
    [ -f "${K_NFS}" ] && core_dir="$(cat ${K_NFS})${core_dir}"

    # Print files under ${coredir}
    LogRun 'find "${core_dir}" 2>&1'
    dump_file_path=$(ls -t -1 "${core_dir}"/*/${file_name} 2>/dev/null | head -1)
    if [ -z "${dump_file_path}" ]; then
        Error "No ${file_name} saved in ${core_dir}."
        return 1
    else
        LogRun "file -i ${dump_file_path}"
        Log "${file_name} path: ${dump_file_path}"
        return 0
    fi
}

GetCorePath()
{
    vmcore=""
    GetDumpFile "vmcore"
    if [ $? -ne 0 ]; then
        Error "Failed to find vmcore file. Please check kdump process in console.log"
        Report
    elif [ ! -s "${dump_file_path}" ]; then
        Error "The vmcore is empty. Please check kdump process in console.log"
        Report
    fi
    vmcore="${dump_file_path}"
}

CheckVmlinux()
{
    vmlinux="/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"
    [ ! -f "${vmlinux}" ] && MajorError "vmlinux not found."

    # validate kernel-debuginfo file sanity
    rpm -V "${K_NAME%-core}-debuginfo" || {
        ls -l "/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"
        MajorError "${K_NAME%-core}-debuginfo file sanity check failed"
    }
}

# Run crash cmd defined in $cmd_file. Only return code is checked.
# Output:
#   ${cmd_file%.*}.log if on a live system
#   ${cmd_file%.*}.vmcore.log if on a vmcore
CrashCommand_CheckReturnCode()
{
    local args=$1; shift
    local aux=$1; shift
    local core=$1; shift
    local cmd_file=${1:-"crash-simple.cmd"}; shift
    local log_suffix
    [ -z "$core" ] && log_suffix=log || log_suffix="${core##*/}.log"

    Log "Check the return code of this session"
    Log "# crash ${args} -i ${K_TESTAREA}/${cmd_file} ${aux} ${core}"

    if [ -f "${K_TESTAREA}/${cmd_file}" ]; then
        # The EOF part is the workaround of the the crash utility bug
        # 458422 -- [RFE] Scripting Friendly, which has only been fixed
        # in RHEL5.3. Otherwise, the crash utility session would fail
        # during the initialization when invoked from a script without a
        # control terminal.
        crash ${args} -i "${K_TESTAREA}/${cmd_file}" ${aux} ${core} \
                > "${K_TESTAREA}/${cmd_file%.*}.$log_suffix" 2>&1 <<EOF
EOF
        retval=${PIPESTATUS[0]}

        RhtsSubmit "${K_TESTAREA}/${cmd_file%.*}.$log_suffix"
        RhtsSubmit "${K_TESTAREA}/${cmd_file}"

        if [ ${retval} -eq 0 ]; then
            return 0
        else
            Error "crash returns error code ${retval}."
            return $retval
        fi

    fi
}

# Run crash cmd defined in $cmd_file. Check if output contains potential errors.
# Output:
#   ${cmd_file%.*}.log if on a live system
#   ${cmd_file%.*}.vmcore.log if on a vmcore
CrashCommand_CheckOutput()
{
    local args=$1; shift
    local aux=$1; shift
    local core=$1; shift
    local cmd_file=${1:-"crash.cmd"}; shift
    local log_suffix
    [ -z "$core" ] && log_suffix=log || log_suffix="${core##*/}.log"

    local retval=0

    Log "Check command output of this session."
    if [ -f "${K_TESTAREA}/${cmd_file}" ]; then
        Log "# crash ${args} -i \"${K_TESTAREA}/${cmd_file}\" ${aux} ${core}"
        crash ${args} -i "${K_TESTAREA}/${cmd_file}" ${aux} ${core} \
                > "${K_TESTAREA}/${cmd_file%.*}.$log_suffix" 2>&1 <<EOF
EOF
        retval=${PIPESTATUS[0]}

        RhtsSubmit "${K_TESTAREA}/${cmd_file%.*}.$log_suffix"
        RhtsSubmit "${K_TESTAREA}/${cmd_file}"

        if [ ${retval} -ne 0 ]; then
            Error "Crash returned error code ${retval}."
        fi

        ValidateCrashOutput "${K_TESTAREA}/${cmd_file%.*}.$log_suffix" || retval=$((retval+1))
        if [ "${retval}" -ne 0 ]; then return 1; fi

        Log "Crash successfully analysed vmcore (See ${cmd_file%.*}.$log_suffix for more details)"
        return 0
    fi
}

ValidateCrashOutput()
{
    local cmd_output_file=$1
    local result=0

    [ -z "$cmd_output_file" ] && return 1

    # Crash does not return sensitive error codes.
    Log "Skip patterns when searching for potential errors."

    # Bug 1074523 - [RHEL7] [crash] 3.10.0-106.el7 c000000057cd7900:
    # event_attr_PM_L2_CO_FAIL_BUSY_p+24 000000003eb46c8a
    echo "- '_FAIL_'"

    # Bug 1188446 - [RHEL-7.1-20150115.0][crash] Instruction bus error [400] exception frame
    # this is not a bug, it is simply a left-over exception frame that was
    # found by the "bt -E" option
    echo "- 'Instruction bus error [***] exception frame:'"

    # In aarch64 vmcore analyse testing, the "err" string that is passed to __die() is
    # preceded by "Internal error: ", shown here in "arch/arm64/kernel/traps.c".
    # PANIC: "Internal error: Oops: 96000047 [#1] SMP" (check log for details)'
    echo "- 'PANIC'"

    # Dave Anderson <anderson@redhat.com> updated the pageflags_data in
    # crash-7.0.2-2.el7 to include the use of '00000002: error' which
    # causes /kernel/kdump/analyse-crash to FAIL.
    echo "- '00000002: error'"

    # We have seen those false negative results before
    # e00000010a3b2980 e000000110198fb0 e000000118f09a10 REG
    # /var/log/cups/error_log
    echo "- 'error_'"

    # flags: 6 (KDUMP_CMPRS_LOCAL|ERROR_EXCLUDED)
    echo "- 'ERROR_'"

    # e00000010fe82c60 e000000118f0a328 REG
    # usr/lib/libgpg-error.so.0.3.0
    echo "- '-error'"

    # [0] divide_error
    # [16] coprocessor_error
    # [19] simd_coprocessor_error
    echo "- '_error'"

    # Data Access error  [301] exception frame:
    echo "- 'Data Access error'"

    # fph = {{
    #     u = {
    #       bits = {3417217742307420975, 65598},
    #       __dummy = <invalid float value>
    #     }
    #   }, {
    echo "- 'invalid float value'"


    # crash> foreach crash task
    # ...
    # fail_nth = 0
    echo "- 'fail_nth'"

    # [ffff81007e565e48] __down_failed_interruptible at ffffffff8006468b
    echo "- '_fail'"

    # crash> bt -r/-F
    # ffff800019553c20:  0000000000000063 failed_resume+16
    # failed_resume is normal function name.
    echo "- 'failed_resume'"

    # @aarch64:
    # crash> bt -r/-F
    # ffff800083fabb20: 0000000000000063 failed_freeze+24
    # failed_freeze is normal function name.
    echo "- 'failed_freeze'"
    # ffff80008cfb3a90:  0000000000000063 failed_prepare+16
    echo "- 'failed_prepare'"

    # ffff80000b2a2f40:  ffff09d9882f3980 __event_xfs_inode_free_eofblocks_invalid
    # __event_xfs_inode_free_eofblocks_invalid: function name
    echo "- 'event_xfs_inode_free_eofblocks_invalid'"

    # crash> bt -t
    # ffff80001865bb20:  0000000000000063 failed_suspend
    # failed_suspend is normal function name.
    echo "- 'failed_suspend'"

    #       failsafe_callback_cs = 97,
    #       failsafe_callback_eip = 3225441872,
    echo "- 'failsafe'"

    # crash> mod
    #      MODULE       NAME                      SIZE  OBJECT FILE
    # ...
    # ffffffffc0310080  failover                 16384  (not loaded)  [CONFIG_KALLSYMS]
    echo "- 'failover'"

    # [ffff81003ee83d60] do_invalid_op at ffffffff8006c1d7
    # [6] invalid_op
    # [10] invalid_TSS
    echo "- 'invalid_'"

    # [253] invalidate_interrupt
    echo "- 'invalidate'"

    # name: a00000010072b4e8  "PCIBR error"
    echo "- 'PCIBR error'"

    # name: a000000100752ce0  "TIOCE error"
    echo "- 'TIOCE error'"

    # [c0000003e46423f0] xlog_state_ioerror at d000000002c867e8 [xfs]
    echo "- 'xlog_state_ioerror'"

    # beaker testing harness has a process 'beah-beaker-bac' which
    # will open a file named  /var/beah/journals/xxxxx/debug/task_beah_unexpected
    # which will be showed by 'foreach files'
    echo "- 'task_beah_unexpected'"

    # arm-smmu-v3-gerror is an IRQ line implemented in some aarch64 machines
    # like Qualcomm Amberwing (CPU: Centriq 2400)
    # crash> irq 124
    # IRQ   IRQ_DESC/_DATA      IRQACTION      NAME
    # 124  ffff8017d8d2f000  ffff8017d8d0e280  "arm-smmu-v3-gerror"
    echo "- 'arm-smmu-v3-gerror'"

    # Since crash-7.2.7-2.el8, it implemented a new "error" environment variable
    # crash> set c2fe8000
    #      PID: 15917
    #     ...skipping...
    #          error: default
    echo "- 'error: default'"

    # crash> bt -r
    #   ffff800d0d075df0:  ffff800d0d075e60 __should_failslab+216
    #   ffff800d0d075e00:  ffff800dc001ae00 failslab
    echo "- 'failslab'"

    # crash> bt -a
    #   ...skipping..
    #0 [c0000001f3a1b810] .creds_are_invalid at c0000000001630c4
    echo "- 'creds_are_invalid'"

    Log "Search patterns for potential errors."

    echo "- 'fail'"
    echo "- 'error'"
    echo "- 'invalid'"

    # BZ 449111 - makedumpfile corrupts vmcore on ia64: crash's bt
    #             fails to unwind
    echo "- 'absurdly large unwind_info'"

    # BZ 458417 - SIGSEGV when search -k on IA64
    # Second issue,
    # crash> search -k deadbeef
    # search: ia64_VTOP(a000000200000000): unexpected region 5 address
    echo "- 'unexpected'"

    # BZ 1369808 - crash fails to analyse vmcore on mustang because
    #              makedumpfile filters/excludes required pages
    echo "- 'crash: page excluded: kernel virtual address'"

    # BZ 1312738 - crash: zero-size memory allocation (aarch64)
    echo "- 'zero-size memory allocation'"

    # BZ 1662039 - crash command fails to display disk I/O statistics (dev -d/-D)
    # and PCI device data (dev -p)
    echo "- 'dev: -d option not supported or applicable on this architecture or kernel'"
    echo "- 'dev: -D option not supported or applicable on this architecture or kernel'"
    # dev -p is supported on RHEL5 and RHEL8.
    echo "- 'dev: -p option not supported or applicable on this architecture or kernel'"

    # crash> bt -r
    # ...
    # c0000007ed8b2be0:  rmqueue_bulk.constprop.25+192 fail_page_alloc
    echo "- 'fail_page_alloc'"

    # On Fedora32
    # crash> help -v
    # ...
    # pageflags_data:
    # ...
    #   [8] 00000100: error
    echo "- '00000100: error'"

    # On RHEL9
    # crash> help -n
    # ...
    # sub_header_kdump: 562feebe11f0
    # ...
    # size_vmcoreinfo: 2972 (0xb9c)
    #       OFFSET(printk_ringbuffer.fail)=72
    echo "- 'printk_ringbuffer.fail'"


    # Skip false warnings.
    #   mod: cannot find or load object file for crasher/altsysrq module
    #   (cannot determine file and line number)
    #
    # [Bug 495586] [RHEL5.3 GA] The result of crash 'bt -a' subcommand
    # is not output when analysing dom0 kernel
    #
    # PID: 8709 TASK: ed13c550 CPU: 6 COMMAND: "diff" bt: starting
    # backtrace locations of the active (non-crashing) xen tasks cannot
    # be determined: try -t or -T options
    #
    # when vmcore dumped by virsh dump --crash, there would be no 'panic process'
    # 'WARNING: panic task not found'
    #
    # [Bug 1552446] crash-gcore-command
    # WARNING: page fault at
    #   It's a normal warning messeage. They are simply pages in the task's
    #   address space that were never instantiated.
    # WARNING: FPU may be inaccurate
    #   Benigh warning that crash-time state of the FPU cannot be gathered
    #   from the dumpfile
    #
    # [Bug 1630770] crash ELF vmcore: bt reports 'bt: cannot determine
    # NT_PRSTATUS ELF note for active task: c000003fe65bdd00
    #
    #   bt: cannot determine NT_PRSTATUS ELF note for active task
    #   bt: WARNING: cannot determine starting stack frame for task
    #   WARNING: cannot find NT_PRSTATUS note for cpu
    #
    # On RHEL8
    # crash> foreach bt
    #   ...skipping...
    #   PID: 669      TASK: c00000001e683400  CPU: 8    COMMAND: "systemd-journal"
    #   ....skipping...
    #   DSISR: 0000000042000000     Syscall Result: 0000000000000000
    #   cannot find the stack info.
    #
    # Search for the following words for warnings.
    #   warning
    #   warnings
    #   cannot
    Log "WARNING MESSAGES BEGIN"
    grep -v \
         -e "mod: cannot find or load object file for crasher module" \
         -e "mod: cannot find or load object file for altsysrq module" \
         -e "mod: cannot find or load object file for crash_warn module" \
         -e "mod: cannot find or load object file for hung_task module" \
         -e "mod: cannot find or load object file for lkdtm module" \
         -e "bt: cannot determine NT_PRSTATUS ELF note for active task" \
         -e "bt: WARNING: cannot determine starting stack frame for task" \
         -e "cannot determine file and line number" \
         -e "cannot be determined: try -t or -T options" \
         -e "WARNING: kernel relocated" \
         -e "WARNING: page fault at" \
         -e "WARNING: FPU may be inaccurate" \
         -e "WARNING: cannot find NT_PRSTATUS note for cp" \
         -e "cannot find the stack info." \
         "${cmd_output_file}" |
    if [ -n "${SKIP_WARNING_PAT}" ]; then grep -v -e "${SKIP_WARNING_PAT}"; else cat; fi |
        grep -iw -e 'warning' \
             -e 'warnings' \
             -e 'cannot' \
             2>&1 | tee -a "${OUTPUTFILE}"
    local warnFound=${PIPESTATUS[2]}
    Log "WARNING MESSAGES END"

    if [ "${warnFound}" -eq 0 ]; then
        Warn "Crash commands reported warnings."
        result=1
    fi

    Log "ERROR MESSAGES BEGIN"
    grep -v -e '_FAIL_' \
         -e 'PANIC:' \
         -e 'Instruction bus error  \[[0-9]*\] exception frame:' \
         -e '00000002: error' \
         -e 'error_' \
         -e 'ERROR_' \
         -e '-error' \
         -e '_error' \
         -e 'Data Access error' \
         -e 'invalid float value' \
         -e 'fail_nth' \
         -e '_fail' \
         -e 'failed_resume' \
         -e 'failed_freeze' \
         -e 'failed_prepare' \
         -e 'event_xfs_inode_free_eofblocks_invalid' \
         -e 'failed_suspend' \
         -e 'failsafe' \
         -e 'failover' \
         -e 'invalid_' \
         -e 'invalidate' \
         -e 'PCIBR error' \
         -e 'TIOCE error' \
         -e 'task_beah_unexpected' \
         -e 'arm-smmu-v3-gerror' \
         -e 'xlog_state_ioerror' \
         -e 'fail_page_alloc' \
         -e 'error: default' \
         -e 'failslab' \
         -e 'creds_are_invalid' \
         -e '00000100: error' \
         -e 'printk_ringbuffer.fail' \
         "${cmd_output_file}" |
    if [ -n "${SKIP_ERROR_PAT}" ]; then grep -v -e "${SKIP_ERROR_PAT}"; else cat; fi |
        grep -i -e 'fail' \
             -e 'error' \
             -e 'invalid' \
             -e 'absurdly large unwind_info' \
             -e 'unexpected' \
             -e 'crash: page excluded: kernel virtual address' \
             -e 'zero-size memory allocation' \
             -e 'dev: -d option not supported or applicable on this architecture or kernel' \
             -e 'dev: -D option not supported or applicable on this architecture or kernel' \
             -e 'dev: -p option not supported or applicable on this architecture or kernel' \
             2>&1 | tee -a "${OUTPUTFILE}"
    local errorFound=${PIPESTATUS[2]}

    Log "ERROR MESSAGES END"

    if [ "${errorFound}" -eq 0 ]; then
        Error "Crash commands reported errors."
        result=1
    fi

    return $result
}

CrashCommand()
{
    local args=$1; shift
    local aux=$1; shift
    local core=$1; shift
    # allow passing cmd file other than default crash.cmd or crash-simple.cmd
    local cmd_file=$1; shift

    local retval=0
    if [ -z "$cmd_file" ]; then
        # If cmd_file is not provided,
        # run CheckRuturnCode on simple-cmd and CheckOutput on common-cmd
        CrashCommand_CheckReturnCode "${args}" "${aux}" "${core}" "${cmd_file}"
        retval=$?
        CrashCommand_CheckOutput "${args}" "${aux}" "${core}" "${cmd_file}"
    elif [ "$cmd_file" = "crash-simple.cmd" ]; then
        # If cmd_file is "crash-simple.cmd", run CheckRuturnCode only.
        CrashCommand_CheckReturnCode "${args}" "${aux}" "${core}" "${cmd_file}"
    else
        # If a non-simple cmd is provided, run CheckOutput only.
        CrashCommand_CheckOutput "${args}" "${aux}" "${core}" "${cmd_file}"
    fi

    retval=$((retval+$?))
}

CrashExtensionLoadTest()
{
    local arg=$1
    [ -z "$arg" ] && {
        Error "No plugin is specified for crash extension loading tests."
        return
    }

    local cmd="${K_TESTAREA}/crash_plugin_load.cmd"
    cat <<EOF >"$cmd"
extend ${arg}.so
exit
EOF
    local test_log=${cmd%.*}.log

    RhtsSubmit "$cmd"
    Log "Run cmd: #crash -i $cmd ${vmlinux} > ${test_log}"
    crash -i "$cmd" "${vmlinux}" > "${test_log}"
    RhtsSubmit "${test_log}"
    grep "shared object loaded" "${test_log}" || {
        Error "Failed to load the Crash extension. Please read crash_plugin_load.log for details".
    }
}
