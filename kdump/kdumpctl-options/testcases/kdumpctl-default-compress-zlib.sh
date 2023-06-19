#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

# Bug 2078461 - [IBM 8.8 FEAT] kdump to use zlib/dfltcc as default to improve compression speed and ratio on IBM z15 and above
# Fixed in RHEL-8.8 kexec-tools-2.0.25-3.el8.

# Bug 2078460 - [IBM 9.2 FEAT] kdump to use zlib/dfltcc as default to improve compression speed and ratio on IBM z15 and above
# Fixed in RHEL-9.2 kexec-tools-2.0.25-8.el9.


if [ "${RELEASE}" -lt 8 ] || [ "$(uname -m)" != "s390x" ]; then
    Skip "This feature is not supported."
    Report
fi

if $IS_RHEL9;then
    CheckSkipTest kexec-tools 2.0.25-8 && Report
elif $IS_RHEL8;then
    CheckSkipTest kexec-tools 2.0.25-3 && Report
fi

DefaultConfigCheck()
{
    RhtsSubmit "$KDUMP_CONFIG"

    LogRun "grep -v '#' ${KDUMP_CONFIG}"

    if ! grep -q -v '#' ${KDUMP_CONFIG} | grep -q 'makedumpfile -c'; then
        Error "It did not use zlib as default kdump compression method."
    fi
}

MultihostStage "$(basename "${0%.*}")" DefaultConfigCheck
