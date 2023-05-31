#!/usr/bin/bash

# regression test for https://gitlab.com/cki-project/upt/-/issues/118

echo "SERVERS: $SERVERS"
echo "CLIENTS: $CLIENTS"

echo "hostname: $HOSTNAME"

if echo "$SERVERS" | grep -q "$HOSTNAME"; then
    # Running as server
    echo "Running as server..."
    # We want it to finish after client
    rstrnt-sync-block -s CLIENT_DONE "$CLIENTS"
    sleep 10
    rstrnt-report-result "${RSTRNT_TASKNAME}" PASS
else
    # Client just return
    echo "Running as client..."
    rstrnt-report-result "${RSTRNT_TASKNAME}" FAIL
    rstrnt-sync-set -s CLIENT_DONE
fi
