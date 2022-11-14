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
The worknode.linux.util.dhclient module provides a class (dhclient) that
represents the dhclient command line executable.

"""

__author__ = 'Ken Benoit'

import re

from constants.time import *
from worknode.exception.worknode_executable import *
import worknode.worknode_executable
import worknode.command_parser

class dhclient(worknode.worknode_executable.WorkNodeExecutable):
    """
    dhclient represents the dhclient command line executable, which provides a
    way to request an IP address from a DHCP server.

    """
    def __init__(self, work_node, command = 'dhclient'):
        super(dhclient, self).__init__(work_node)
        self.__command = command
        self.__options = []
        self.__success_regexes = []
        self.__failure_regexes = []

    def get_command(self, command_arguments = None):
        """
        Get the full command to be executed.

        Keyword arguments:
        command_arguments - Argument string to feed to the command.

        Return value:
        Full command to be executed.

        """
        full_command = self.__command + ' '

        for option in self.get_options():
            full_command += option + ' '

        if command_arguments is not None:
            full_command += ' ' + command_arguments

        return full_command

    def add_option(self, option_flag, option_value = None):
        """
        Add a command line option to supply with the command.

        Keyword arguments:
        option_flag - Option flag to supply.
        option_value - Value to supply with the option flag.

        """
        self.__options.append(option_flag)
        if option_value is not None:
            self.__options.append(option_value)

    def get_options(self):
        """
        Get a list of command line options to supply with the command.

        Return value:
        List of command line options.

        """
        return self.__options

    def add_success_regular_expression(self, regex):
        """
        Add a regular expression that indicates when the command has
        successfully completed.

        Keyword arguments:
        regex - Regular expression.

        """
        self.__success_regexes.append(regex)

    def add_failure_regular_expression(self, regex):
        """
        Add a regular expression that indicates when the command has failed to
        successfully complete.

        Keyword arguments:
        regex - Regular expression.

        """
        self.__failure_regexes.append(regex)

    def run_command(self, command_arguments = None, timeout = HOUR):
        """
        Request an IP address from a DHCP server.

        Keyword arguments:
        command_arguments - Argument string to feed to the command.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        Return value:
        List of command output.

        """
        failure_found = False
        full_command = self.get_command(command_arguments = command_arguments)
        regexes = []
        for regex in self.__success_regexes:
            regexes.append(regex)
        for regex in self.__failure_regexes:
            regexes.append(regex)
        output = super(dhclient, self)._run_command(command = full_command, timeout = timeout, wait_for_regex = regexes)
        for line in output:
            for regex in self.__failure_regexes:
                if re.search(regex, line):
                    failure_found = True
                    raise FailedCommandOutputError("dhclient failed to bind an address")
        return output

