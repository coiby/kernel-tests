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
The worknode.linux.util.systemctl module provides a class (systemctl) that
represents the systemctl command line executable.

"""

__author__ = 'Ken Benoit'

import re

import worknode.worknode_executable

class systemctl(worknode.worknode_executable.WorkNodeExecutable):
    """
    systemctl represents the systemctl command line executable, which provides a
    command line method for interacting with system services.

    """
    def __init__(self, work_node, command = 'systemctl'):
        super(systemctl, self).__init__(work_node)
        self.__command = command

    def get_command(self, command_arguments = None):
        """
        Get the command to execute.

        Keyword arguments:
        command_arguments - Argument string to feed to the command.

        Return value:
        Command string.

        """
        full_command = self.__command
        if command_arguments is not None:
            full_command += ' ' + command_arguments
        return full_command

    def run_command(self, command_arguments = None, timeout = 5):
        """
        Run the command and return any output.

        Keyword arguments:
        command_arguments - Argument string to feed to the command.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        Return value:
        Command output.

        """
        full_command = self.get_command(command_arguments = command_arguments)
        output = super(systemctl, self)._run_command(command = full_command, timeout = timeout)

        return output

    def start(self, unit_name):
        """
        Start a unit (service).

        Keyword arguments:
        unit_name - Name of the unit (service) to start.

        """
        command_arguments = "start {0}".format(unit_name)
        output = self.run_command(command_arguments = command_arguments)

    def stop (self, unit_name):
        """
        Stop a unit (service).

        Keyword arguments:
        unit_name - Name of the unit (service) to stop.

        """
        command_arguments = "stop {0}".format(unit_name)
        output = self.run_command(command_arguments = command_arguments)

    def restart(self, unit_name):
        """
        Restart a unit (service).

        Keyword arguments:
        unit_name - Name of the unit (service) to restart.

        """
        command_arguments = "restart {0}".format(unit_name)
        output = self.run_command(command_arguments = command_arguments)

    def get_status(self, unit_name):
        """
        Get the status of a unit (service).

        Keyword arguments:
        unit_name - Name of the unit (service) to get the status.
        
        Return value:
        String of status output.

        """
        command_arguments = "status {0}".format(unit_name)
        output = self.run_command(command_arguments = command_arguments)
        return ''.join(output)

    def is_running(self, unit_name):
        """
        Check if the unit (service) is currently running.

        Keyword arguments:
        unit_name - Name of the unit (service) to check the run status.

        Return value:
        True if the unit (service) is currently running. False otherwise.

        """
        running = False
        status_output_string = self.get_status(unit_name = unit_name)
        if re.search('\(running\)', status_output_string):
            running = True
        return running

