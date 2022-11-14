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
The worknode.linux.util.modprobe module provides a class (modprobe) that
represents the modprobe command line executable.

"""

__author__ = 'Ken Benoit'

import re

import worknode.worknode_executable
import worknode.command_parser

class modprobe(worknode.worknode_executable.WorkNodeExecutable):
    """
    modprobe represents the modprobe command line executable, which provides a
    command line utility for intelligently inserting and removing kernel
    modules.

    """
    def __init__(self, work_node, command = 'modprobe'):
        super(modprobe, self).__init__(work_node)
        self.__command = command
        self.__failure_regex = None

    def set_failure_regular_expression(self, regex):
        """
        Set a regular expression to verify the command output against to see if
        the command hasn't run successfully.

        Keyword arguments:
        regex - Regular expression that can be used to verify command failure.

        """
        self.__failure_regex = regex

    def run_command(self, command_arguments = None, timeout = 5):
        """
        Run the command and return the parsed output.

        Keyword arguments:
        command_arguments - Argument string to feed to the command.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        """
        full_command = self.__command + ' ' + command_arguments
        output = super(modprobe, self)._run_command(command = full_command, timeout = timeout)
        for line in output:
            if self.__failure_regex is not None:
                if re.search(self.__failure_regex, line):
                    raise FailedCommandOutputError("{0} did not run successfully".format(self.__command))


