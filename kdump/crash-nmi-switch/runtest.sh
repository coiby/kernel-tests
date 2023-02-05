#!/bin/sh

# Copyright (c) 2012 Red Hat, Inc. All rights reserved. This copyrighted material
# is made available to anyone wishing to use, modify, copy, or
# redistribute it subject to the terms and conditions of the GNU General
# Public License v.2.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# Author: WANG Chao <chaowang@redhat.com>

# Source Kdump tests common functions.
. ../include/runtest.sh

LoadIPMI()
{
    Log "Load IPMI modules"

    rpm -q --quiet Openipmi ipmitool || InstallPackages OpenIPMI ipmitool
    service ipmi start || MajorError 'Start ipmi daemon failed'

    echo 1 > /proc/sys/kernel/panic_on_unrecovered_nmi
    echo 1 > /proc/sys/kernel/unknown_nmi_panic
    echo 1 > /proc/sys/kernel/panic
}


TriggerNMICrash()
{
    # Trigger NMI switch by common IPMI interface
    ipmitool power diag
}


Multihost SystemCrashTest TriggerNMICrash LoadIPMI
