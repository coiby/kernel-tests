#!/usr/bin/python
# Copyright (c) 2014 Red Hat, Inc. All rights reserved. This copyrighted material
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
# Author: Ken Benoit

"""
The worknode.linux.util.rhel7.systemctl module provides a class (systemctl) that
represents the systemctl command line executable on RHEL7.

"""

__author__ = 'Ken Benoit'

import worknode.linux.util.systemctl

class systemctl(worknode.linux.util.systemctl.systemctl):
    """
    systemctl represents the systemctl command line executable, which provides a
    command line method for interacting with system services.

    """
    def __init__(self, work_node, command = 'systemctl'):
        super(systemctl, self).__init__(work_node = work_node, command = command)

