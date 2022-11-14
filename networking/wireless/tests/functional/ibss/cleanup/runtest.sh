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

export PYTHONPATH=../../../../test-framework:../../../../wireless_tests:$PYTHONPATH

command_arguments=""
if [ -n "${NETWORK_NAME+1}" ]
then
command_arguments="$command_arguments --network_name $NETWORK_NAME"
fi

function uninstall_packages()
{
    local package_names="$1"

    # Try dnf if available
    if command -v dnf &> /dev/null
    then
        rlRun "dnf -y remove $package_names" 0
        return 0
    fi
    # Try yum if available
    if command -v yum &> /dev/null
    then
        rlRun "yum -y remove $package_names" 0
        return 0
    fi

    rlFail "Unable to find a package installer"
    exit 1
} # uninstall_packages

# Server (IBSS access point) code
Server()
{
    rlJournalStart
        rlPhaseStartCleanup
            rhts-sync-block -s "CLIENT_CLEANUP_DONE" "$CLIENTS"
            # Check if the ad_hoc_server is already installed
            if rlCheckRpm ad_hoc_server
            then
                rlRun -l "uninstall_packages 'ad_hoc_server'" 0 "Uninstall the ad_hoc_server service"
            else
                # If the ad_hoc_server binary isn't installed then build it
                rlFail
            fi
            # Perform the sync-up between client and server
            rhts-sync-set -s "SERVER_CLEANUP_DONE"
        rlPhaseEnd
    rlJournalEnd
    rlJournalPrintText
} # Server

# Client (system connected to IBSS) code
Client()
{
    rlJournalStart
        rlPhaseStartCleanup
            # Run the client connection script
            rlRun -l "./client.py --rest_server ${SERVERS} ${command_arguments}" 0 "Disconnect from the IBSS"
            # Perform the sync-up between client and server after the server has finished setting up
            rhts-sync-set -s "CLIENT_CLEANUP_DONE"
            # Perform the sync up between the client and server after the client has finished connecting
            rhts-sync-block -s "SERVER_CLEANUP_DONE" "$SERVERS"
        rlPhaseEnd
    rlJournalEnd
    rlJournalPrintText
} # Client

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
if  test -z "$JOBID" ; then
    echo "Variable jobid not set! Assume developer mode"
    export DEVMODE=true
fi

# If SERVERS and/or CLIENTS is not defined then we have no idea how to run this
# multihost test
if [ -z "$SERVERS" ] || [ -z "$CLIENTS" ]; then
    rlFail "Cannot determine test type! Client/Server Failed:"
    exit 1
fi

if i_am_server
then
    Server
else
    Client
fi
