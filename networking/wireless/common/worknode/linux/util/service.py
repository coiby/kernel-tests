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
The worknode.linux.util.service module provides a class (service) that
represents the service command line executable.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_executable

class service(worknode.worknode_executable.WorkNodeExecutable):
    """
    service represents the service command line executable, which provides a
    command line method for interacting with system services.

    """
    def __init__(self, work_node, command = 'service'):
        super(service, self).__init__(work_node)
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

    def run_command(self, command_arguments = None, timeout = 30):
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
        output = super(service, self)._run_command(command = full_command, timeout = timeout)

        return output

    def start(self, service_name):
        """
        Start a service.

        Keyword arguments:
        service_name - Name of the service to start.

        """
        command_arguments = "{0} start".format(service_name)
        output = self.run_command(command_arguments = command_arguments)

    def stop (self, service_name):
        """
        Stop a service.

        Keyword arguments:
        service_name - Name of the service to stop.

        """
        command_arguments = "{0} stop".format(service_name)
        output = self.run_command(command_arguments = command_arguments)

    def restart(self, service_name):
        """
        Restart a service.

        Keyword arguments:
        service_name - Name of the service to restart.

        """
        command_arguments = "{0} restart".format(service_name)
        output = self.run_command(command_arguments = command_arguments)

    def get_status(self, service_name):
        """
        Get the status of a service.

        Keyword arguments:
        service_name - Name of the service to get the status.
        
        Return value:
        String of status output.

        """
        command_arguments = "status {0}".format(service_name)
        output = self.run_command(command_arguments = command_arguments)
        return ''.join(output)

    def is_running(self, service_name):
        """
        Check if the service is currently running.

        Keyword arguments:
        service_name - Name of the service to check the run status.

        Return value:
        True if the service is currently running. False otherwise.

        """
        running = False
        status_output_string = self.get_status(service_name = service_name)
        if re.search('\(running\)', status_output_string):
            running = True
        return running

