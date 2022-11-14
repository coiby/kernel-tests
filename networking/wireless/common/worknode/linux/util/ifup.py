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
The worknode.linux.util.ifup module provides a class (ifup) that represents the
executable used to bring a network interface up.

"""

__author__ = 'Ken Benoit'

import re

import worknode.worknode_executable
from worknode.exception.worknode_executable import *

class ifup(worknode.worknode_executable.WorkNodeExecutable):
    """
    ifup represents the command used to bring a network interface up.

    """
    def __init__(self, work_node, command = 'ifup'):
        super(ifup, self).__init__(work_node)
        self.__command = command

    def _set_success_regex(self, regex):
        self.__success_regex = regex

    def run_command(self, interface_name, timeout = 30):
        """
        Run the command.

        Keyword arguments:
        interface_name - Name of the network interface.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        """
        full_command = self.__command + ' ' + interface_name
        output = super(ifup, self)._run_command(command = full_command, timeout = timeout)
        found_success = False
        for line in output:
            if re.search(self.__success_regex, line):
                found_success = True
                break
        if not found_success:
            raise FailedCommandOutputError("ifup failed to bring up the network interface")

