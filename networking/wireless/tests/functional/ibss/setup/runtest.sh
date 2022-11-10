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

wireless_firmware="iwl100-firmware iwl105-firmware iwl135-firmware iwl1000-firmware iwl2000-firmware iwl2030-firmware iwl3160-firmware iwl3945-firmware iwl4965-firmware iwl5000-firmware iwl5150-firmware iwl6000-firmware iwl6050-firmware iwl7260-firmware iwl6000g2a-firmware iwl6000g2b-firmware"

function install_packages()
{
    local package_names="$1"
    local local_install="$2"

    # Try dnf if available
    if command -v dnf &> /dev/null
    then
        rlRun "dnf -y install $package_names" 0
        return 0
    fi
    # Try yum if available
    if command -v yum &> /dev/null
    then
        if (( local_install == 1 ))
        then
            rlRun "yum -y localinstall $package_names" 0
            return 0
        else
            rlRun "yum -y install $package_names" 0
            return 0
        fi
    fi

    rlFail "Unable to find a package installer"
    exit 1
} # install_packages

# Server (IBSS access point) code
Server()
{
    rlJournalStart
        rlPhaseStartSetup
            # Get any ad_hoc_server service build dependencies installed
            rlRun -l "install_packages 'python3 python3-devel rpm-build' 0" 0 "Install the build dependencies"

            # Check if firmware packages have been installed
            local needed_packages=""
            for package in $wireless_firmware
            do
                if ! rlCheckRpm "$package"
                then
                    needed_packages="$needed_packages $package"
                fi
            done

            # If there are any firmware packages missing then install and then reboot
            if [[ -n $needed_packages ]]
            then
                rlRun -l "install_packages '$needed_packages' 0" 0 "Install the build dependencies"
                rhts-reboot
            fi

            # Check if the ad_hoc_server is already installed
            if rlCheckRpm ad_hoc_server
            then
                # Check to see if the ad_hoc_server service isn't running
                if ! systemctl is-active ad_hoc_server
                then
                    # Start the service if it isn't running
                    systemctl start ad_hoc_server
                fi
            else
                # If the ad_hoc_server binary isn't installed then build it
                rlRun -l "rpmbuild -bb --define '_topdir ${PWD}/ad_hoc_server' ad_hoc_server/SPECS/ad_hoc_server.spec" 0 "Build the ad_hoc_server service"
                rlRun -l "install_packages 'ad_hoc_server/RPMS/noarch/ad_hoc_server-*.rpm' 1" 0 "Install the ad_hoc_server service"
                rhts-reboot
            fi
            # Perform the sync-up between client and server
            rhts-sync-set -s "SERVER_SETUP_DONE"
            rhts-sync-block -s "CLIENT_SETUP_DONE" "$CLIENTS"
        rlPhaseEnd
    rlJournalEnd
    rlJournalPrintText
} # Server

# Client (system connecting to IBSS) code
Client()
{
    rlJournalStart
        rlPhaseStartSetup
            # Do some initial dependency installations
            if ! rlCheckRpm python-requests
            then
                rlRun -l "install_packages 'python-requests' 0" 0 "Install test dependencies"
            fi
            if rlIsRHEL > 7.0
            then
                if ! rlCheckRpm NetworkManager-wifi
                then
                    rlRun -l "install_packages 'NetworkManager-wifi' 0" 0 "Install test dependencies"
                    rhts-reboot
                fi
            fi

            # Check if firmware packages have been installed
            local needed_packages=""
            for package in $wireless_firmware
            do
                if ! rlCheckRpm "$package"
                then
                    needed_packages="$needed_packages $package"
                fi
            done

            # If there are any firmware packages missing then install and then reboot
            if [[ -n $needed_packages ]]
            then
                rlRun -l "install_packages '$needed_packages' 0" 0 "Install the test dependencies"
                rhts-reboot
            fi

            # Perform the sync-up between client and server after the server has finished setting up
            rhts-sync-block -s "SERVER_SETUP_DONE" "$SERVERS"
            # Run the client connection script
            rlRun -l "./client.py --rest_server ${SERVERS} ${command_arguments}" 0 "Configure and connect to the IBSS"
            # Perform the sync up between the client and server after the client has finished connecting
            rhts-sync-set -s "CLIENT_SETUP_DONE"
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
