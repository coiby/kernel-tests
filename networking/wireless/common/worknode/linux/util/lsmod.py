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
The worknode.linux.util.lsmod module provides a class (lsmod) that represents
the lsmod command line executable.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_executable
import worknode.command_parser

class lsmod(worknode.worknode_executable.WorkNodeExecutable):
    """
    lsmod represents the lsmod command line executable, which provides a 
    command line utility for gathering a listing of kernel modules currently in
    use.

    """
    def __init__(self, work_node, command = 'lsmod'):
        super(lsmod, self).__init__(work_node)
        self.__objects = {}
        self.__command = command
        self.__command_parser = None

    def initialize_command_parser(self, output_type):
        """
        Initialize the command parser for the command.

        Keyword arguments:
        output_type - The format the output is expected to be displayed.

        Return value:
        Parser object (worknode.command_parser)

        """
        if output_type == 'key-value':
            self.__command_parser = worknode.command_parser.KeyValueParser()
        elif output_type == 'table':
            self.__command_parser = worknode.command_parser.TableParser()
        elif output_type == 'single':
            self.__command_parser = worknode.command_parser.SingleValueParser()
        return self.__command_parser

    def get_command_parser(self):
        """
        Get the command parser for the command.

        Return value:
        Parser object (worknode.command_parser)

        """
        return self.__command_parser

    def run_command(self, command_arguments = None, timeout = 5):
        """
        Run the command and return the parsed output.

        Keyword arguments:
        command_arguments - Argument string to feed to the command.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        Return value:
        Parsed output (a dictionary if key-value, a list of dictionaries
        if table)

        """
        full_command = self.__command
        if command_arguments is not None:
            full_command += ' ' + command_arguments
        output = super(lsmod, self)._run_command(command = full_command, timeout = timeout)
        command_parser = self.get_command_parser()
        if command_parser is not None:
            parsed_output = command_parser.parse_raw_output(output = output)
            return parsed_output

    def get_module_list(self):
        """
        Get a list of the modules currently in-use and the modules using those
        modules.

        Return value:
        TODO

        """
