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
The worknode.command_manager module provides a class (CommandManager) that
manages multiple work node executables to use in a failback method.

"""

__author__ = 'Ken Benoit'

import framework
from worknode.exception.worknode_executable import WorkNodeExecutableException

class CommandManager(framework.Framework):
    """
    CommandManager provides a manager object that allows for multiple work node
    executable objects to be stored for referencing and make it possible to
    handle a situation where an executable that fails automatically tries to run
    the next executable in line.

    """
    def __init__(self):
        super(CommandManager, self).__init__()
        self.__command_methods = {}
        self.__command_argument_map = {}
        self.__standard_arguments = []
        self.__priority = []

    def clear_method_arguments(self):
        """
        Clear the method arguments stored in this manager.

        """
        self.__standard_arguments = []

    def add_method_arguments(self, arguments):
        """
        Add a list of argument keywords that are meant to be fed to the command
        methods being stored in this manager.

        Keyword arguments:
        arguments - List of argument keywords.

        """
        for argument in arguments:
            self.__standard_arguments.append(argument)

    def add_command_method(self, command_method, command_name, argument_map = {}):
        """
        Add a command method to the manager.

        Keyword arguments:
        command_method - Method to a command object.
        command_name - Name to associate with the command for future
                       referencing.
        argument_map - Dictionary of the mapping of the command manager
                       arguments to the command method arguments.

        """
        self.__command_methods[command_name] = command_method
        self.__command_argument_map[command_name] = {}
        self.__priority.append(command_name)
        for standard_argument_name, method_argument_name in argument_map.items():
            self.__command_argument_map[command_name][standard_argument_name] = method_argument_name

    def run_command(self, arguments = {}, command_name = None):
        """
        Run a command method with the provided arguments (the standard arguments
        defined previously. They will be mapped out to the correct arguments for
        whatever method is being called).

        Keyword arguments:
        arguments - Dictionary of arguments and values to pass into the command
                    method.
        command_name - If provided then the command name provided will be the
                       only command used when attempting to run the command.

        """
        if command_name is None:
            success = False
            for command in self.__priority:
                try:
                # Try running the command method
                    self.__execute_command_method(
                        command_name = command,
                        arguments = arguments,
                    )
                except WorkNodeExecutableException:
                # If we have a work node executable exception proceed to the
                # command method
                    continue
                else:
                # If we didn't encounter a work node executable exception then
                # break out of the loop
                    success = True
                    break
            if not success:
                raise Exception(
                    "Unable to successfully execute the command after using "
                    + "all available command methods"
                )
        else:
            try:
                self.__execute_command_method(
                    command_name = command_name,
                    arguments = arguments,
                )
            except WorkNodeExecutableException:
                raise Exception(
                    "Unable to successfully execute the command method for "
                    + "{0}".format(command_name)
                )

    def set_priority(self, priority_list):
        """
        Set the command method priority (overrides the priority automatically
        set by add_command_method).

        Keyword arguments:
        priority_list - List of command names in priority order (first to
                        execute first and so on).

        """
        if type(priority_list) is not list:
            raise Exception("priority_list should be a list")
        self.__priority = []
        for command_name in priority_list:
            if command_name not in self.__command_methods.keys():
                raise Exception(
                    "{0} is not a currently defined command method".format(
                        command_name
                    )
                )
            self.__priority.append(command_name)

    def __execute_command_method(self, command_name, arguments = {}):
        mapped_arguments = {}
        for argument_name, argument_value in arguments.items():
            if argument_name not in self.__standard_arguments:
                raise Exception(
                    "Argument {0} was not predefined".format(
                        argument_name
                    )
                )
            method_argument_name = self.__command_argument_map[command_name][argument_name]
            mapped_arguments[method_argument_name] = argument_value
        self.__command_methods[command_name](**mapped_arguments)
