#!/bin/sh

# Setup Shell options.
set -o xtrace -o pipefail

echo "- start of test."
echo "- run command:"
echo "- eval ${TESTARGS:-${CMDS_TO_RUN}}"

eval ${TESTARGS:-${CMDS_TO_RUN}}
code=${PIPESTATUS[0]}
if [ ${code} -ne 0 ]; then
    echo "- fail: unexpected error code ${code}."
    result="FAIL"
else
    echo "- pass: the command returns 0."
    result="PASS"
fi

echo "- end of test."
if command -v rstrnt-report-result; then
    rstrnt-report-result "${RSTRNT_TASKNAME:-distribution/command}" "${result}" "${code}"
else
    exit "$code"
fi
