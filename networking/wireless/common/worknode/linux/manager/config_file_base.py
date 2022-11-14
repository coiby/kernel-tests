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
The worknode.linux.manager.config_file_base module provides a class
(ConfigFileManager) that manages the config files present on the work node.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_component_manager

class ConfigFileManager(worknode.worknode_component_manager.WorkNodeComponentManager):
    """
    ConfigFileManager is an object that manages the config files present on the
    work node. It acts as a container for accessing the config files.

    """
    def __init__(self, parent):
        super(ConfigFileManager, self).__init__(parent = parent)
        self.__config_file_objects = {}

    def _add_config_file_object(self, config_file_name, config_file_object):
        self.__config_file_objects[config_file_name] = config_file_object

    def get_config_file_object(self, config_file_name):
        """
        Get the config file object associated with the config file name
        specified.

        Keyword arguments:
        config_file_name - Name of the config file.

        Return value:
        Object representing the config file.

        """
        return self.__config_file_objects[config_file_name]
