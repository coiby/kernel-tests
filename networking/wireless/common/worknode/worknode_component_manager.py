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
The worknode.worknode_component_manager module provides a standard base class
(WorkNodeComponentManager) for all work node component manager classes to
inherit from.

"""

__author__ = 'Ken Benoit'

import framework

class WorkNodeComponentManager(framework.Framework):
    """
    WorkNodeComponentManager provides a unified way of managing a specific
    work node component, such as everything networking-related.

    """
    def __init__(self, parent):
        super(WorkNodeComponentManager, self).__init__()
        self.__parent = parent
        self.__commands = {}

    def _get_parent(self):
        return self.__parent

    def _get_work_node(self):
        return self._get_parent()

    def add_command(self, command_name, command_object):
        """
        Adds a command object to the manager.

        Keyword arguments:
        command_name - Name to associate with the command.
        command_object - WorkNodeExecutable object that will execute the
                         command.

        Return value:
        WorkNodeExecutable object.

        """
        self.__commands[command_name] = command_object
        return self.__commands[command_name]

    def get_command_object(self, command_name):
        """
        Get the requested command object.

        Keyword arguments:
        command_name - Name associated with the command.

        Return value:
        WorkNodeExecutable object.

        """
        if command_name not in self.__commands:
            raise NameError("Command object for {0} doesn't exist".format(command_name))
        return self.__commands[command_name]

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent})'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
        )
