#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   include.sh of /kernel/hw-enablement/removable-media/include
#   Description: Libraries and helper files for testing of removable media devices
#   Author: Mike Gahagan <mgahagan@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Test parameters
DEV=$TEST_PARAM_TEST_DEV
SIZE=$TEST_PARAM_TEST_SIZE

# Generate test parameters
function build_params()
{
local params=""
if [[ -n "$DEV" ]] ; then
  params="$params -d $DEV"
fi

if [[ -n "$SIZE" ]] ; then
  params="$params -s $SIZE"
fi
echo "$params"
}

# Check for the presense of the dt rpm package and install repo and package if necessary
function install_dt()
{
    echo "Checking for dt..."
    yum list installed dt > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        echo "dt is already installed.."
        return 0
    else
        yum list available dt > /dev/null 2>&1
        echo "Installing dt..."
        yum -y install dt
        if [ $? -eq 0 ] ; then
            echo "dt installed sucessfully..."
            echo "confirming dt binary is present and executable...."
            if [ -x /usr/sbin/dt ] ; then
                echo "dt appears functional..."
                return 0
            else
                echo "Problem with dt installation..."
                return 1
            fi
        else
            echo "dt installation failed"
            return 1
        fi
    fi
}

