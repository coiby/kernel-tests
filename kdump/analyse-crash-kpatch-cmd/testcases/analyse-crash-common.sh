#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

analyse()
{
    # Get the kpatch
    local kpatch_module=$(kpatch list | grep -i enabled | tail -n 1 | awk '{print $1}')
    [ -z ${kpatch_module} ] && {
        Error "Failed to find kpatch module"
        return
    }

    # Check command output of this session.
    cat <<EOF >"${K_TESTAREA}/crash.cmd"
mod -s "${kpatch_module}"
EOF

    for func_name in ${KPATCH_FUNC_LIST};
    do
        cat <<EOF >>"${K_TESTAREA}/crash.cmd"
l ${func_name}
dis -l ${func_name}
EOF
    done

    cat <<EOF >>"${K_TESTAREA}/crash.cmd"
exit
EOF

    CheckVmlinux
    GetCorePath

    # Skip error messages
    # crash> mod -s kpatch_4_18_0_107_0_1_test
    # BFD: BFD (GNU Binutils) 2.23.52.20130312 assertion fail elf.c:1877
    export SKIP_ERROR_PAT="assertion fail"
    # shellcheck disable=SC2154
    CrashCommand "" "${vmlinux}" "${vmcore}" "crash.cmd"
    export SKIP_ERROR_PAT=

    # Validate
    local crash_output_file="${K_TESTAREA}/crash.vmcore.log"

    Log "Validating patched functions in crash output."
    for func_name in ${KPATCH_FUNC_LIST};
    do
        # Expect report 'duplicate symbols' for patched function.
        # And 'dis -l $func' should list patched function with kpatch module.
        # For example,
        # crash> dis -l cmdline_proc_show
        # dis: cmdline_proc_show: duplicate text symbols found:
        # c00000000046b7b0 (t) cmdline_proc_show /usr/src/debug/kernel-3.10.0-1048.el7/linux-3.10.0-1048.el7.ppc64le/fs/proc/cmdline.c: 7
        # d000000005810790 (t) cmdline_proc_show [kpatch_3_10_0_1048_0_1_test]
        grep -i "${func_name}" < "$crash_output_file" | grep "duplicate text symbols found"
        [ $? -ne 0 ] && Error "Expect 'dis: ${func_name}: duplicate text symbols found' but not found."

        grep -i "${func_name}" < "$crash_output_file" | grep "\[${kpatch_module}\]"
        [ $? -ne 0 ] && Error "Expect '${func_name}: \[${kpatch_module}\]' but not found."
    done
    Log "Done validating patched functions."

    rm -f "${K_TESTAREA}/crash.cmd"
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" analyse
