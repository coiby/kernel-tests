#!/usr/bin/python
# Copyright (c) 2016 Red Hat, Inc. All rights reserved. This copyrighted material
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
The worknode.linux.util.rhel6.hciconfig module provides a class (hciconfig) that
represents the hciconfig command line executable.

"""

__author__ = 'Ken Benoit'

import worknode.linux.util.hciconfig

class hciconfig(worknode.linux.util.hciconfig.hciconfig):
    """
    hciconfig represents the hciconfig command line executable, which provides a
    command line for configuring local Bluetooth devices.

    """
    def __init__(self, work_node, command = 'hciconfig'):
        super(hciconfig, self).__init__(
            work_node = work_node,
            command = command
        )
        self.__configure_hciconfig_commands()

    def __configure_hciconfig_commands(self):
        # Add all the hciconfig commands
        up_commands = self.add_hciconfig_command(
            command_string = 'up',
        )
        down_commands = self.add_hciconfig_command(
            command_string = 'down',
        )

    def bring_controller_up(self, interface_name):
        """
        Bring the indicated local Bluetooth controller up.

        Keyword arguments:
        interface_name - Name of the local Bluetooth interface (typically
                         "hciX" where X is the interface number).

        """
        self.get_hciconfig_command(
            command_string = 'up'
        ).run_command(interface_name = interface_name.lower())

    def bring_controller_down(self, interface_name):
        """
        Bring the indicated local Bluetooth controller down.

        Keyword arguments:
        interface_name - Name of the local Bluetooth interface (typically
                         "hciX" where X is the interface number).

        """
        self.get_hciconfig_command(
            command_string = 'down'
        ).run_command(interface_name = interface_name.lower())
