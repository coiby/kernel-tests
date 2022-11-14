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
The worknode.linux.util.ifdown module provides a class (ifdown) that represents
the executable used to bring a network interface down.

"""

__author__ = 'Ken Benoit'

import re

import worknode.worknode_executable
from worknode.exception.worknode_executable import *

class ifdown(worknode.worknode_executable.WorkNodeExecutable):
    """
    ifdown represents the command used to bring a network interface down.

    """
    def __init__(self, work_node, command = 'ifdown'):
        super(ifdown, self).__init__(work_node)
        self.__command = command
        self.__success_regex = None

    def _set_success_regex(self, regex):
        self.__success_regex = regex

    def run_command(self, interface_name, timeout = 10):
        """
        Run the command.

        Keyword arguments:
        interface_name - Name of the network interface.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        """
        full_command = self.__command + ' ' + interface_name
        output = super(ifdown, self)._run_command(command = full_command, timeout = timeout)
        found_success = True
        for line in output:
            if re.search(self.__success_regex, line):
                found_success = True
                break
        if not found_success:
            raise FailedCommandOutputError("ifdown failed to bring down the network interface")

