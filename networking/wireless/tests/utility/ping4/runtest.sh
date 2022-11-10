#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Author: Ken Benoit <kbenoit@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
#
#   RedHat Internal.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include rhts environment
. /usr/bin/rhts-environment.sh
if [ -f /usr/lib/beakerlib/beakerlib.sh ]
then
    . /usr/lib/beakerlib/beakerlib.sh
elif [ -f /usr/share/beakerlib/beakerlib.sh ]
then
    . /usr/share/beakerlib/beakerlib.sh
fi

ping_test()
{
    local target="$1"
    local transmit_min=50
    local receive_min=45
    local ping_command="ping -c $transmit_min $target"
    local ping_result
    ping_result=$(rlRun "$ping_command" 0 "Ping target $target")
    rlLogInfo "$ping_result"

    local ping_result
    ping_result=$(echo "$ping_result" | grep "transmitted")

    local receive_count
    receive_count=$(echo "$ping_result" | awk '{print $4}')
    local transmit_count
    transmit_count=$(echo "$ping_result" | awk '{print $1}')

    if [[ $transmit_count -lt $transmit_min ]]
    then
        rlDie "Failed to transmit $transmit_min packets. Transmitted $transmit_count"
    fi
    if [[ $receive_count -lt $receive_min ]]
    then
        rlDie "Failed to receive $receive_min packets. Received $receive_count"
    fi

    return 0
} # ping_test

Server()
{
    rlJournalStart
    local ping_targets=""
    # Check if we have a predefined ping target
    if [[ -z $PING_TARGET ]]
    then
        # If not then grab all of the IPv4 addresses currently defined
        rlPhaseStartSetup
            local targets
	    targets=$(ip route | grep src | awk '{print $9}')
            for client in $CLIENTS
            do
                # And send each IPv4 address to the client
                for target in $targets
                do
                    rhts-sync-block -s "CLIENT_REQUESTING_$HOSTNAME" "$client"
                    sleep 2
                    echo "$target" | nc "$client" 10013
                done
                # And then let the client know that we don't have any more
                # addresses
                rhts-sync-block -s "CLIENT_REQUESTING_$HOSTNAME" "$client"
                sleep 2
                echo "done" | nc "$client" 10013
            done
        rlPhaseEnd
    # If we have a predefined ping target then set that in our ping targets
    # list
    else
        ping_targets="$PING_TARGET"
    fi
    # If we have any ping targets then ping each target (should only happen
    # if we have a predefined ping target)
    rlPhaseStartTest
        for target in $ping_targets
        do
            rlRun "ping_test $target" 0 "Ping target $target"
        done
    rlPhaseEnd
    rlPhaseStartCleanup
        # Do one final sync-up with the client(s)
        for client in $CLIENTS
        do
            rhts-sync-block -s "CLIENT_DONE" "$client"
        done
        # And then indicate that this server is done
        rhts-sync-set -s "SERVER_DONE"
    rlPhaseEnd
    rlJournalEnd
    rlJournalPrintText
} # Server

Client()
{
    rlJournalStart
    for client in $CLIENTS
    do
        if [[ $client == "$HOSTNAME" ]]
        then
            local ping_targets=""
            # Check if we have a predefined ping target
            if [[ -z $PING_TARGET ]]
            then
                # If not then grab all of the IPv4 addresses currently
                # defined on the server
                rlPhaseStartSetup
                    for server in $SERVERS
                    do
                        while true
                        do
                            # Request an IPv4 address from the server
                            rhts-sync-set -s "CLIENT_REQUESTING_$server"
			    local target
			    target=$(nc -l 10013)
                            # If we get the string "done" then the server
                            # has sent us all of its addresses and we should
                            # break out of the loop
                            if [[ $target == "done" ]]
                            then
                                break
                            fi
                            # Make sure we add any ping targets received to
                            # our ping target list
                            rlLogDebug "Adding $target as a ping target"
                            ping_targets="$ping_targets $target"
                        done
                    done
                rlPhaseEnd
            # If we have a predefined ping target then set that in our ping
            # targets list
            else
                ping_targets="$PING_TARGET"
            fi
            # If we have any ping targets then ping each target
            rlPhaseStartTest
                for target in $ping_targets
                do
                    rlRun "ping_test $target" 0 "Ping target $target"
                done
            rlPhaseEnd
            # Check if this is the only client. If not, set up a sync for
            # the next client
            if [[ $client != "$CLIENTS" ]]
            then
                rhts-sync-set -s "NEXT_CLIENT"
                break
            fi
        else
            rhts-sync-block -s "NEXT_CLIENT" "$client"
        fi
    done
    rlPhaseStartCleanup
        # Let the server(s) know the test is done
        rhts-sync-set -s "CLIENT_DONE"
        # Make sure the server(s) are done as well
        for server in $SERVERS
        do
            rhts-sync-block -s "SERVER_DONE" "$server"
        done
    rlPhaseEnd
    rlJournalEnd
    rlJournalPrintText
} # Client

Standalone()
{
    rlJournalStart
        if [[ -z $PING_TARGET ]]
        then
            rlLog "Using default value for PING_TARGET"
            PING_TARGET="beaker.engineering.redhat.com"
        fi
        rlPhaseStartTest
            ping_targets="$PING_TARGET"
            for target in $ping_targets
            do
                rlRun "ping_test $target" 0 "Ping target $target"
            done
        rlPhaseEnd
    rlJournalEnd
    rlJournalPrintText
} # Standalone

# Check if the system this script is being run on is in the SERVERS list
i_am_server()
{
    echo "$SERVERS" | grep -q "$HOSTNAME"
} # i_am_server

# Check if the system this script is being run on is in the CLIENTS list
i_am_client()
{
    echo "$CLIENTS" | grep -q "$HOSTNAME"
} # i_am_client

# If we don't have a job ID then this is probably being run locally in developer
# mode
if  test -z "$JOBID"
then
    echo "Variable jobid not set! Assume developer mode"
    export DEVMODE=true
fi

if i_am_server
then
    Server
elif i_am_client
then
    Client
else
    Standalone
fi
