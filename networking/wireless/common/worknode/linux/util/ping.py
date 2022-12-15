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
The worknode.linux.util.ping module provides a class (ping) that represents the
ping command line executable.

"""

__author__ = 'Ken Benoit'

import re

from worknode.exception.worknode_executable import *
import worknode.worknode_executable
import worknode.command_parser
from constants.time import *

class ping(worknode.worknode_executable.WorkNodeExecutable):
    """
    ping represents the ping command line executable, which provides a way to
    detect if a target IP address is up and being used.

    """
    def __init__(self, work_node, command = 'ping'):
        super(ping, self).__init__(work_node)
        self.__command = command
        self.__success_regex = None

    def get_command(self):
        """
        Get the base command.

        Return value:
        Command string.

        """
        return self.__command

    def set_success_regular_expression(self, regex):
        """
        Set a regular expression to verify the command output against to see if
        the command has run successfully.

        Keyword arguments:
        regex - Regular expression that can be used to verify command success.

        """
        self.__success_regex = regex

    def run_command(self, command_arguments = None, timeout = HOUR):
        """
        Ping the destination.

        Keyword arguments:
        command_arguments - Argument string to feed to the command.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        """
        results_found = False
        full_command = self.get_command()
        if command_arguments is not None:
            full_command += ' ' + command_arguments
        output = super(ping, self)._run_command(command = full_command, timeout = timeout)
        for line in output:
            if self.__success_regex is not None:
                if re.search(self.__success_regex, line):
                    results_found = True
                    break
            if results_found:
                break
        if not results_found:
            raise FailedCommandOutputError("{0} did not run successfully".format(self.get_command()))

