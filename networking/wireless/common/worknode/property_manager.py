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
The worknode.property_manager module provides a standard base class
(PropertyManager) for all property manager classes to inherit from.

"""

__author__ = 'Ken Benoit'

import framework
import time
from constants.time import *
import worknode.command_parser

class PropertyManager(framework.Framework):
    """
    PropertyManager provides a unified way of caching and updating properties.
    It provides a means of having a set of commands assigned to each individual
    property so as to allow for a failback process in the case of the command
    failing to provide any values (if the command is unavailable). Providing a
    command, parser, and property mapping for each command manager allows the
    properties to be queried, cached, and have automatic refreshing of the
    cached data on a cache miss or when an optional staleness timer is reached.

    """
    def __init__(self, work_node):
        super(PropertyManager, self).__init__()
        self.__properties = {}
        self.__property_timers = {}
        self.__command_managers = {}
        self.__work_node = work_node
        self.__command_manager_to_property_map = {}

    def add_command_manager(self, manager_name, command):
        """
        Adds a command manager.

        Keyword arguments:
        manager_name - A name to associate with the manager.
        command - The command to use to get the properties.

        Return value:
        CommandManager object.

        """
        self.__command_managers[manager_name] = CommandManager(command = command, work_node = self.__work_node)
        self.__command_manager_to_property_map[manager_name] = []
        return self.__command_managers[manager_name]

    def get_command_manager(self, manager_name):
        """
        Get the specified command manager.

        Keyword arguments:
        manager_name - Name associated with the manager.

        Return value:
        CommandManager object.

        """
        return self.__command_managers[manager_name]

    def set_property_staleness_timer(self, property_name, timespan):
        """
        Set the staleness timespan for the internal property provided.

        Keyword arguments:
        property_name - The internally referenced property name.
        timespan - Time (in seconds) that needs to pass before the properties
                   are automatically refreshed upon the next property value
                   query.

        """
        if type(property_name) is not str:
            raise TypeError("property_name needs to be of type str")
        if type(timespan) is not int and timespan is not None:
            raise TypeError("timespan needs to be of type int")

        if property_name not in self.__properties:
            raise NameError("{0} has not been initialized".format(property_name))

        self.__property_timers[property_name] = timespan

    def initialize_property(self, property_name, timespan = None):
        """
        Initialize the supplied property.

        Keyword arguments:
        property_name - The name of the property.
        timespan - Time (in seconds) that needs to pass before the properties
                   are automatically refreshed upon the next property value
                   query.

        """
        if type(property_name) is not str:
            raise TypeError("property_name needs to be of type str")
        if type(timespan) is not int and timespan is not None:
            raise TypeError("timespan needs to be of type int")

        self.__properties[property_name] = CachedProperty(property_manager = self)

        self.set_property(property_name = property_name, property_value = None)
        self.set_property_staleness_timer(property_name = property_name, timespan = timespan)

    def set_property(self, property_name, property_value):
        """
        Set the value of the property.

        Keyword arguments:
        property_name - The name of the property.
        property_value - The value to assign to the property.

        """
        if type(property_name) is not str:
            raise TypeError("property_name needs to be of type str")

        self.__properties[property_name].set_value(property_value = property_value)

    def get_property_value(self, property_name):
        """
        Get the value of the property.

        Keyword arguments:
        property_name - The name of the property.

        Return value:
        The value associated with the property name.

        """
        if self.__properties[property_name].get_value() is None:
            self.refresh_properties()
        if self.__property_timers[property_name] is not None:
            if time.time() - self.__properties[property_name].get_last_update() > self.__property_timers[property_name]:
                self.refresh_properties()
        return self.__properties[property_name].get_value()

    def set_command_priority(self, property_name, command_priority):
        """
        Set the command priority for a property.

        Keyword arguments:
        property_name - Name of the property to set the command priority for.
        command_priority - List of command manager names, in the order they are
                           preferred to be used in.

        """
        for command_manager_name in command_priority:
            if command_manager_name not in self.__command_managers:
                raise Exception("A command manager associated with {0} is not defined".format(command_manager_name))
        if property_name not in self.__properties:
            raise Exception("Property {0} has not been initialized".format(property_name))
        self.__properties[property_name].set_command_priority(command_priority = command_priority)
        for command_manager_name in command_priority:
            self.__command_manager_to_property_map[command_manager_name].append(property_name)

    def refresh_properties(self):
        """
        Refresh all the internally cached properties defined in the property
        manager.

        """
        # Keep a list of refreshed properties
        refreshed_properties = []
        # Loop through the properties
        for (property_name, cached_property) in self.__properties.items():
            # Check to see if this property has already been refreshed
            if cached_property not in refreshed_properties:
                command_priority = cached_property.get_command_priority()
                # Loop through the command managers defined for this property
                for command_manager_name in command_priority:
                    command_manager = self.get_command_manager(manager_name = command_manager_name)
                    property_dictionary = command_manager.run_command()
                    if type(property_dictionary) is not dict:
                        raise Exception("Expected the command manager to return a dictionary")
                    # See if we got a value back from running the command
                    if property_name in property_dictionary:
                        property_names = self.__command_manager_to_property_map[command_manager_name]
                        # Loop through all the properties associated with the
                        # command and refresh them
                        for name in property_names:
                            if name in property_dictionary:
                                self.set_property(property_name = name, property_value = property_dictionary[name])
                                refreshed_properties.append(self.__properties[name])
                        break

    def __del__(self):
        for property_name in list(self.__properties.keys()):
            cached_property = self.__properties[property_name]
            cached_property.delete()
            del self.__properties[property_name]

class CommandManager(framework.Framework):
    """
    Manager that holds a command to execute, the parser to parse the command
    output, and the map of the command output to the property names.

    """
    def __init__(self, command, work_node):
        super(CommandManager, self).__init__()
        self.__command = command
        self.__parser = None
        self.__property_map = {}
        self.__work_node = work_node
        self.__timeout = HOUR

    def get_command(self):
        """
        Get the command being used.

        Return value:
        Command string.

        """
        return self.__command

    def initialize_command_parser(self, parser_type):
        """
        Initialize the command parser for the manager.

        Keyword arguments:
        parser_type - Type of parser to initialize. Parser types are:
                      'key-value', 'single', 'table-row', and 'table'.

        Return value:
        Command parser object.

        """
        if parser_type == 'key-value':
            self.__parser = worknode.command_parser.KeyValueParser()
        elif parser_type == 'single':
            self.__parser = worknode.command_parser.SingleValueParser()
        elif parser_type == 'table-row':
            self.__parser = worknode.command_parser.TableRowParser()
        elif parser_type == 'table':
            self.__parser = worknode.command_parser.TableParser()
        else:
            raise Exception("Unknown parser type provided")
        return self.__parser

    def set_command_parser(self, parser):
        """
        Set the command parser object to use for the manager.

        Keyword arguments:
        parser - Command parser object.

        """
        self.__parser = parser

    def get_command_parser(self):
        """
        Get the command parser.

        Return value:
        Command parser object.

        """
        if self.__parser is None:
            raise Exception("Command parser has not been initialized")
        return self.__parser

    def set_property_mapping(self, command_property_name, internal_property_name):
        """
        Set a mapping between the property name used by the parser and the name
        of the property as it is being used in the property manager.

        Keyword arguments:
        command_property_name - Property name returned back by the parser.
        internal_property_name - Property name used by the property manager.

        """
        self.__property_map[command_property_name] = internal_property_name

    def set_timeout(self, timespan):
        """
        Set the maximum amount of time to wait for the command to complete.

        Keyword arguments:
        timespan - Time (in seconds) to wait for the command to complete.

        """
        self.__timeout = timespan

    def run_command(self):
        """
        Run the stored command, parse it, and return back a dictionary of the
        values with the keys being the internal property names.

        Return value:
        Dictionary of the property values assigned to the internal property
        names.

        """
        output = self.__work_node.run_command(command = self.__command, timeout = self.__timeout)
        parsed_output = self.__parser.parse_raw_output(output = output)
        property_dictionary = {}
        if type(parsed_output) is dict:
            for (key, value) in parsed_output.items():
                if key in self.__property_map:
                    property_dictionary[self.__property_map[key]] = value
            return property_dictionary
        elif type(parsed_output) is list:
            for row in parsed_output:
                for (key, value) in row.items():
                    if key in self.__property_map:
                        if self.__property_map[key] in property_dictionary:
                            property_dictionary[self.__property_map[key]].append(value)
                        else:
                            property_dictionary[self.__property_map[key]] = [value]
        else:
            raise TypeError("Unknown parsed output type returned after running the command")
        return property_dictionary

class CachedProperty(framework.Framework):
    """
    CachedProperty represents a property that has been cached in the property
    manager.

    """
    def __init__(self, property_manager):
        super(CachedProperty, self).__init__()
        self.__property_value = []
        self.__last_update = None
        self.__command_priority = []
        self.__property_manager = property_manager

    def get_value(self):
        """
        Get the currently cached property value.

        Return value:
        Property value.

        """
        return self.__property_value

    def set_value(self, property_value):
        """
        Set the value of the cached property.

        Keyword arguments:
        property_value - Value to store for the property.

        """
        self.__property_value = property_value
        self.__last_update = time.time()

    def delete(self):
        """
        Delete the cached property.

        """
        del self

    def get_last_updated_time(self):
        """
        Get the last time (in seconds since the Epoch) that the property was
        updated.

        Return value:
        Time (in seconds since the Epoch).

        """
        return self.__last_update

    def get_command_priority(self):
        """
        Get the list of command manager names in priority order.

        Return value:
        List of command manager names.

        """
        return self.__command_priority

    def set_command_priority(self, command_priority):
        """
        Set the list of command manager names in the order they should be tried.

        Keyword arguments:
        command_priority - List of command manager names.

        """
        self.__command_priority = command_priority
