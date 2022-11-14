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
The vendor_manager_base module provides a base class (VendorManager) for
VendorManager objects to inherit from.

"""

__author__ = 'Ken Benoit'

import framework

class VendorManager(framework.Framework):
    """
    VendorManager provides a base for VendorManager objects to inherit from. A
    VendorManager provides vendor-specific features for a network interface
    card, such as debugfs support.

    """
    def __init__(self, parent):
        super(VendorManager, self).__init__()
        self.__vendor_id = None
        self.__device_id = None
        self.__debugfs_manager = None
        self.__parent = parent

    def _get_parent(self):
        return self.__parent

    def _get_work_node(self):
        interface = self._get_parent()
        return interface._get_work_node()

    def _set_vendor_id(self, id_string):
        self.__vendor_id = id_string

    def _set_device_id(self, id_string):
        self.__device_id = id_string

    def _set_debugfs_manager(self, manager):
        self.__debugfs_manager = manager

    def get_vendor_id(self):
        return self.__vendor_id

    def get_device_id(self):
        return self.__device_id

    def get_debugfs_manager(self):
        return self.__debugfs_manager

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent})'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
        )

class DebugFSManager(framework.Framework):
    """
    DebugFSManager provides a class to manage all aspects of the debugfs
    implementation of a network interface.

    """
    def __init__(self, parent):
        super(DebugFSManager, self).__init__()
        self.__parent = parent
        self.__debugfs_path = {}

    def _get_parent(self):
        return self.__parent

    def set_path(self, label, path):
        """
        Set a path in the debugfs with a descriptive label for easy recall.

        Keyword arguments:
        label - A descriptive label of the path to be used for later recall.
        path - Path in the debugfs of the specific file.

        """
        self.__debugfs_path[label] = path

    def get_path(self, label):
        """
        Get a path in the debugfs given a specific label.

        Keyword arguments:
        label - A descriptive label previously used to set a path.

        Return value:
        String of a debugfs file path.

        """
        if label not in self.__debugfs_path:
            raise KeyError("Label '{0}' was not previously set".format(label))
        return self.__debugfs_path[label]

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent})'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
        )
