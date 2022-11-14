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
The worknode.worknode_executable module provides a standard base class
(WorkNodeExecutable) for all work node component manager classes to
inherit from.

"""

__author__ = 'Ken Benoit'

import re

import framework
from worknode.exception import *
from constants.time import *

class WorkNodeExecutable(framework.Framework):
    """
    WorkNodeExecutable represents a specific command to execute on a work node,
    along with a property manager to manage the properties associated with the
    command output.

    Keyword arguments:
    work_node - Work node object that the command is being executed on.

    """
    def __init__(self, work_node):
        super(WorkNodeExecutable, self).__init__()
        self.__work_node = work_node

    def _get_work_node(self):
        return self.__work_node

    def _run_command(self, command, timeout = HOUR, wait_for_regex = None):
        work_node = self._get_work_node()
        output = work_node.run_command(command = command, timeout = timeout, wait_for_regex = wait_for_regex)
        if re.search('command not found', ''.join(output)):
            raise CommandNotFoundError('Command executable not found on the work node')
        return output

    def _run_interactive_command(self, command):
        work_node = self._get_work_node()
        process = work_node.start_process(command = command)
        return process
