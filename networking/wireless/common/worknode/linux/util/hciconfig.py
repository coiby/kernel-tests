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
The worknode.linux.util.hciconfig module provides a class (hciconfig) that
represents the hciconfig command line executable.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_executable
import worknode.command_parser

class hciconfig(worknode.worknode_executable.WorkNodeExecutable):
    """
    hciconfig represents the hciconfig command line executable, which provides a
    command line for configuring local Bluetooth devices.

    """
    def __init__(self, work_node, command = 'hciconfig'):
        super(hciconfig, self).__init__(work_node = work_node)
        self.__commands = {}
        self.__command = command

    def get_command(self):
        """
        Get the base command.

        Return value:
        Command string.

        """
        return self.__command

    def add_hciconfig_command(self, command_string):
        """
        Adds an hciconfig command.

        Keyword arguments:
        command_string - The long form string that needs to be supplied to
                         hciconfig to execute the command.

        Return value:
        HciconfigCommand

        """
        if type(command_string) is not str:
            raise TypeError("command_string needs to be of type str")
        self.__commands[command_string] = \
            worknode.linux.util.hciconfig.hciconfig.HciconfigCommand(
                command_string = command_string,
                work_node = self._get_work_node(),
                parent_object = self,
            )
        return self.__commands[command_string]

    def get_hciconfig_command(self, command_string):
        """
        Get an hciconfig command.

        Keyword arguments:
        command_string - The long form string that needs to be supplied to
                         hciconfig to execute the command.

        Return value:
        HciconfigCommand

        """
        if type(command_string) is not str:
            raise TypeError("command_string needs to be of type str")
        if command_string not in self.__commands:
            raise NameError(
                "hciconfig command is not defined for {0}".format(
                    command_string
                )
            )
        return self.__commands[command_string]

    class HciconfigCommand(worknode.worknode_executable.WorkNodeExecutable):
        """
        hciconfig has various command it can execute.

        """
        def __init__(self, command_string, work_node, parent_object):
            super(
                worknode.linux.util.hciconfig.hciconfig.HciconfigCommand,
                self
            ).__init__(work_node = work_node)
            self.__command_string = command_string
            self.__parent_object = parent_object
            self.__options = []
            self.__command_parser = None

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

        def _get_parent_object(self):
            return self.__parent_object

        def get_command_string(self):
            """
            Get the string used for the command.

            Return value:
            String to use when running the command for the object.

            """
            return self.__command_string

        def initialize_command_parser(self, output_type):
            """
            Initialize the command parser for the command.

            Keyword arguments:
            output_type - The format the output is expected to be displayed.

            Return value:
            Parser object (worknode.command_parser)

            """
            if output_type == 'key-value':
                self.__command_parser = \
                    worknode.command_parser.KeyValueParser()
            elif output_type == 'table':
                self.__command_parser = \
                    worknode.command_parser.TableParser()
            elif output_type == 'single':
                self.__command_parser = \
                    worknode.command_parser.SingleValueParser()
            return self.__command_parser

        def get_command_parser(self):
            """
            Get the command parser for the command.

            Return value:
            Parser object (worknode.command_parser)

            """
            return self.__command_parser

        def run_command(
            self,
            interface_name,
            command_arguments = None,
            timeout = 5
            ):
            """
            Run the command and return the parsed output.

            Keyword arguments:
            interface_name - Name of the local Bluetooth interface (typically
                             "hciX" where X is the interface number).
            command_arguments - Argument string to feed to the command.
            timeout - Maximum timespan (in seconds) to wait for the process to
                      finish execution.

            Return value:
            Parsed output (a dictionary if key-value, a list of dictionaries
            if table)

            """
            full_command = self.get_command(
                interface_name = interface_name,
                command_arguments = command_arguments,
            )
            output = super(
                worknode.linux.util.hciconfig.hciconfig.HciconfigCommand,
                self
            )._run_command(command = full_command, timeout = timeout)
            command_parser = self.get_command_parser()
            if command_parser is not None:
                parsed_output = command_parser.parse_raw_output(output = output)
                return parsed_output

        def get_command(self, interface_name, command_arguments = None):
            """
            Get the full command to be executed.

            Keyword arguments:
            interface_name - Name of the local Bluetooth interface (typically
                             "hciX" where X is the interface number).
            command_arguments - Argument string to feed to the command.

            Return value:
            Full command to be executed.

            """
            full_command = ''
            command_string = self.get_command_string()
            hciconfig_string = self._get_parent_object().get_command()

            full_command += hciconfig_string + ' '
            for option in self.get_options():
                full_command += option + ' '
            full_command += interface_name + ' '

            full_command += command_string

            if command_arguments is not None:
                full_command += ' ' + command_arguments

            return full_command
