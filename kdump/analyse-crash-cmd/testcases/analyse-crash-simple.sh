#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

analyse()
{
    # Only check the return code of this session.
    cat <<EOF > "${K_TESTAREA}/crash-simple.cmd"
bt -a
ps
log
exit
EOF

    CheckVmlinux
    GetCorePath

    [ -f "${K_TESTAREA}/crash-simple.vmcore.log" ] && rm -f "${K_TESTAREA}/crash-simple.vmcore.log"
    # shellcheck disable=SC2154
    CrashCommand "" "${vmlinux}" "${vmcore}" "crash-simple.cmd"
    rm -f "${K_TESTAREA}/crash-simple.cmd"
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" analyse

