#!/bin/sh

# Source Kdump tests common functions.
. ../include/runtest.sh

MakedumpfileTest()
{
    GetCorePath

    result_file="${TESTAREA}/dump_dmesg.log"
    [ -f "${result_file}" ] && rm -f "${result_file}"
    LogRun 'makedumpfile --dump-dmesg "${vmcore}" "${result_file}"'

    [ $? -ne 0 ] && Error "'makedumpfile --dump-dmesg' failed."
    [ -f "${result_file}" ] || Error "No file is generated from 'makedumpfile --dump-dmesg'"

    LogRun 'file -i "${result_file}"'

    RhtsSubmit "${result_file}"
    sync;sync;sync;

    rm -f "${result_file}"
}

#+---------------------------+

MultihostStage "$(basename "${0%.*}")" MakedumpfileTest
