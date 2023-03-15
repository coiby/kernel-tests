#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 1447172 - crash: ppc64 "pte" command displays an incorrect
#               physical address for present pages
# Fixed in RHEL-7.4-alt crash-7.1.9-2.el7.
# Test is only applicable to ppc64/ppc64le
analyse() {
    if [[ "$(uname -m)" != ppc64* ]]; then
        Skip "Test is only applicable to ppc64/ppc64le."
        return
    fi

    CheckSkipTest crash 7.1.9-2 && return

    if ($IS_RHEL5 || $IS_RHEL6) && [[ "$(uname -m)" == ppc64* ]]; then
        Skip "Test is not applicable to ppc64/ppc64le on rhel6 and older releases."
        return
    fi

    # Check command output of this session.
    # Crash commands vm/pte/vtop will be used in this test.

    # Running crash live in background
    cat <<EOF >"sleep.sh"
sleep 300
EOF
    sh ./sleep.sh &

    # Get a valid starting address of virtual address range for CRASH command.
    local script_pid=$(pgrep -a "sleep" | grep "sleep 300" | awk 'END{print $1}')
    Log "Backgroud sleep command pid $script_pid"
    cat <<EOF >"vm.cmd"
vm $script_pid
exit
EOF
    crash -i vm.cmd | tee vm.out
    RhtsSubmit "$(pwd)/vm.cmd"
    RhtsSubmit "$(pwd)/vm.out"
    local addr
    addr=$(grep -i "/usr/bin/sleep" vm.out | head -n 1 | awk '{print $2}')

    # Translate the virtual address to physical address. Get the PTE value
    # from its output

    cat <<EOF >"vtop.cmd"
vtop -c $script_pid -u $addr
exit
EOF
    crash -i vtop.cmd | tee vtop.out
    RhtsSubmit "$(pwd)/vtop.cmd"
    RhtsSubmit "$(pwd)/vtop.out"

    pte_value=$(grep -i "PTE: " vtop.out | awk '{print $4}')
    # Get the 2nd PHYSICAL value in vtop output
    # Because in rhel-alt ppc64le, what physical addr returned in pte cmd can only
    # matches the pattern of 2nd PHYSICAL value in vtop cmd output.
    phy_value=$(sed -n '/PHYSICAL/{n;p;}' vtop.out | awk 'NR==2 {print $2}')

    if [ -z "$pte_value" ] || [ -z "$phy_value" ]; then
        Error "No PTE or Physical address retrieved from vtop cmd result."
        return
    fi

    # Call pte to translate the pte value to phy value.
    cat <<EOF >"pte.cmd"
pte $pte_value
exit
EOF
    crash -i pte.cmd | tee pte.out
    RhtsSubmit "$(pwd)/pte.cmd"
    RhtsSubmit "$(pwd)/pte.out"

    act_pte_value=$(grep -i -A 1 "PTE " pte.out | tail -n 1 | awk '{print $1}')
    act_phy_value=$(grep -i -A 1 "PTE " pte.out | tail -n 1 | awk '{print $2}')

    if [ -z "$act_pte_value" ] || [ -z "$act_phy_value" ]; then
        Error "No PTE or Physical address retrieved from pte cmd result."
    fi

    # Removing leading zero before comparison.
    phy_value=$(echo $phy_value | sed 's/^0*//')
    act_phy_value=$(echo $act_phy_value | sed 's/^0*//')
    if [ "${phy_value}" != "${act_phy_value}" ]; then
        Error "PTE result from pte and vtop is different"
    fi

    ValidateCrashOutput "$(pwd)/vtop.out"
    ValidateCrashOutput "$(pwd)/pte.out"

    Log "Kill the background sleep command"
    LogRun "kill -9 $script_pid"
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" analyse
