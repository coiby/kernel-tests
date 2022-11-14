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
The worknode.linux.util.yum module provides a class (yum) that represents the
executable used to do package management with repositories on rpm-based systems.

"""

__author__ = 'Ken Benoit'

import re

import worknode.worknode_executable
from worknode.exception.worknode_executable import *
from constants.time import *

class yum(worknode.worknode_executable.WorkNodeExecutable):
    """
    yum represents the command used to do package management with repositories
    on rpm-based systems.

    """
    def __init__(self, work_node, command = 'yum'):
        super(yum, self).__init__(work_node = work_node)
        self.__command = command
        self.__list_all_packages = {"command": "", "parser": None}
        self.__list_installed_packages = {"command": "", "parser": None}
        self.__list_updates_packages = {"command": "", "parser": None}
        self.__list_available_packages = {"command": "", "parser": None}
        self.__info_package = {"command": "", "parser": None}
        self.__install_package = {"command": "", "parser": None}

    def _set_listing_all_packages_command(self, command, parser = None):
        self.__list_all_packages['command'] = command
        self.__list_all_packages['parser'] = parser

    def _set_listing_installed_packages_command(self, command, parser = None):
        self.__list_installed_packages['command'] = command
        self.__list_installed_packages['parser'] = parser

    def _set_listing_updates_packages_command(self, command, parser = None):
        self.__list_updates_packages['command'] = command
        self.__list_updates_packages['parser'] = parser

    def _set_listing_available_packages_command(self, command, parser = None):
        self.__list_available_packages['command'] = command
        self.__list_available_packages['parser'] = parser

    def _set_info_package_command(self, command, parser = None):
        self.__info_package['command'] = command
        self.__info_package['parser'] = parser

    def _set_install_package_command(self, command, parser = None):
        self.__install_package['command'] = command
        self.__install_package['parser'] = parser

    def list_all_package_names(self):
        """
        Get a list of all package names (installed and available).

        Return value:
        List of package names.

        """
        package_names = []
        command = self.__list_all_packages['command']
        parser = self.__list_all_packages['parser']
        output = self._run_command(command = command)
        parsed_output = parser.parse_raw_output(output = output)
        for table_row in parsed_output:
            package_names.append(table_row['package_name'])
        return package_names

    def list_installed_package_names(self):
        """
        Get a list of installed package names.

        Return value:
        List of package names.

        """
        package_names = []
        command = self.__list_installed_packages['command']
        parser = self.__list_installed_packages['parser']
        output = self._run_command(command = command)
        parsed_output = parser.parse_raw_output(output = output)
        for table_row in parsed_output:
            package_names.append(table_row['package_name'])
        return package_names

    def list_update_package_names(self):
        """
        Get a list of package names with updates.

        Return value:
        List of package names.

        """
        package_names = []
        command = self.__list_updates_packages['command']
        parser = self.__list_updates_packages['parser']
        output = self._run_command(command = command)
        parsed_output = parser.parse_raw_output(output = output)
        for table_row in parsed_output:
            package_names.append(table_row['package_name'])
        return package_names

    def list_available_package_names(self):
        """
        Get a list of available package names.

        Return value:
        List of package names.

        """
        package_names = []
        command = self.__list_available_packages['command']
        parser = self.__list_available_packages['parser']
        output = self._run_command(command = command)
        parsed_output = parser.parse_raw_output(output = output)
        for table_row in parsed_output:
            package_names.append(table_row['package_name'])
        return package_names
