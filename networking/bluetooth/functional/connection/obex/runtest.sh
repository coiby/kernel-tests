#!/bin/bash


server()
{

    ./test-server.sh &
    pid=$!
    rhts_sync_set -s "SERVER_READY"

    rhts_sync_block -s "CLIENT_LISTENING" ${CLIENTS}
    # Send the Bluetooth controller MAC address to the client
    sleep 30

    hcitool dev | grep -o -E "([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}" | socat - TCP:${CLIENTS}:8080

    rhts_sync_block -s "CLIENT_DONE" ${CLIENTS}

    #kill server; fg is hack around stopped process
    kill $pid && fg

    rhts-submit-log -l /var/log/messages

    return 0

}

client()
{

    rhts_sync_block -s "SERVER_READY" ${SERVERS}

    rhts_sync_set -s "CLIENT_LISTENING"
    # Wait for the server to send the MAC address for its Bluetooth controller
    server_mac=`socat - TCP-LISTEN:8080`

    export MAC="$server_mac"

    rhts-run-simple-test $TEST ./test.sh
    rc=$?
    rhts_sync_set -s "CLIENT_DONE"

    rhts-submit-log -l /var/log/messages

    return $rc
}

RESULT="FAIL"
HOSTNAME=`hostname`

if ! systemctl is-active --quiet bluetooth.service ; then
    systemctl enable --now bluetooth.service
fi

if $(echo $SERVERS | grep -q -i $HOSTNAME)
then
    TEST="$TEST/Server"
    server && RESULT="PASS"

elif $(echo $CLIENTS | grep -q -i $HOSTNAME)
then

    TEST="$TEST/Client"
    client && RESULT="PASS"

else

    echo "Cannot determine test type! Client/Server failed." > ./test.log

fi

rhts-report-result $TEST $RESULT ./test.log
