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
The worknode.linux.util.bluetoothctl module provides a class (bluetoothctl) that
represents the bluetoothctl command line executable.

"""

__author__ = 'Ken Benoit'

import inspect

import worknode.worknode_executable
import worknode.command_parser
from constants.time import *

class bluetoothctl(worknode.worknode_executable.WorkNodeExecutable):
    """
    bluetoothctl represents the bluetoothctl command line executable, which
    provides an interactive command line utility for configuring local and
    remote Bluetooth devices.

    """
    def __init__(self, work_node, command = 'bluetoothctl'):
        super(bluetoothctl, self).__init__(work_node = work_node)
        self.__commands = {}
        self.__command = command

    def get_command(self):
        """
        Get the base command.

        Return value:
        Command string.

        """
        return self.__command

    def add_bluetoothctl_command(self, command_identifier, commands):
        """
        Adds a bluetoothctl command.

        Keyword arguments:
        command_identifier - String to associate with the list of bluetoothctl
                             commands.
        commands - List of bluetoothctl commands to execute.

        Return value:
        BluetoothctlCommand

        """
        if type(command_identifier) is not str:
            raise TypeError("command_identifier needs to be of type str")
        self.__commands[command_identifier] = \
            worknode.linux.util.bluetoothctl.bluetoothctl.BluetoothctlCommand(
                commands = commands,
                work_node = self._get_work_node(),
                parent_object = self,
            )
        return self.__commands[command_identifier]

    def get_bluetoothctl_command(self, command_identifier):
        """
        Get a bluetoothctl command.

        Keyword arguments:
        command_identifier - String associated with a list of bluetoothctl
                             commands.

        Return value:
        BluetoothctlCommand

        """
        if type(command_identifier) is not str:
            raise TypeError("command_identifier needs to be of type str")
        if command_identifier not in self.__commands:
            raise NameError(
                "bluetoothctl command is not defined for {0}".format(
                    command_identifier
                )
            )
        return self.__commands[command_identifier]

    class BluetoothctlCommand(worknode.worknode_executable.WorkNodeExecutable):
        """
        bluetoothctl has various command it can execute.

        """
        def __init__(self, commands, work_node, parent_object):
            super(
                worknode.linux.util.bluetoothctl.bluetoothctl.BluetoothctlCommand,
                self
            ).__init__(work_node = work_node)
            self.__commands = commands
            self.__parent_object = parent_object
            self.__command_parser = None

        def _get_parent_object(self):
            return self.__parent_object

        def get_commands(self):
            """
            Get the list of commands to execute.

            Return value:
            List of commands to execute for the object.

            """
            return list(self.__commands)

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
            elif output_type == 'table-row':
                self.__command_parser = \
                    worknode.command_parser.TableRowParser()
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

        def run_commands(self, command_arguments = [], timeout = HOUR):
            """
            Run the commands and return the parsed output.

            Keyword arguments:
            command_arguments - List of arguments to be passed to each command.
            timeout - Maximum timespan (in seconds) to wait for the process to
                      finish execution.

            Return value:
            Parsed output (a dictionary if key-value, a list of dictionaries
            if table)

            """
            # Get the list of commands to supply to bluetoothctl
            commands = self.get_commands()
            # Make sure we always quit after running all of the commands
            commands.append("quit")

            # If command_arguments wasn't a list make sure we make it into a
            # list
            if type(command_arguments) is not list:
                command_arguments = [command_arguments]

            # If we don't have as many arguments as we do commands then pad out
            # the command arguments list with None
            if len(commands) > len(command_arguments):
                num_extra_commands = len(commands) - len(command_arguments)
                filler_list = [None] * num_extra_commands
                command_arguments = command_arguments + filler_list

            # Start up the interactive bluetoothctl command and grab the process
            process = super(
                worknode.linux.util.bluetoothctl.bluetoothctl.BluetoothctlCommand,
                self
            )._run_interactive_command(
                command = self._get_parent_object().get_command()
            )

            # Run through each command
            for index in range(0, len(commands)):
                command = commands[index]
                # If the command is a string then we will pass it to
                # bluetoothctl
                if type(command) is str:
                    # If the matching argument exists then concatenate the
                    # command and argument together
                    if command_arguments[index] is not None:
                        command += ' ' + str(command_arguments[index])
                    # Send the command to the bluetoothctl process
                    process.send_input(input = command + "\n")
                # If the command isn't a string then check if it is a
                # method/function to execute
                elif inspect.isbuiltin(command) or inspect.isroutine(command):
                    if command_arguments[index] is not None:
                        command(command_arguments[index])
                    else:
                        command()
            # Get all the resulting output of bluetoothctl since it should be
            # finished executing now
            output_lines = process.get_output(all = True)

            # Run the output through the associated parser
            command_parser = self.get_command_parser()
            if command_parser is not None:
                parsed_output = command_parser.parse_raw_output(
                    output = output_lines
                )
                return parsed_output
