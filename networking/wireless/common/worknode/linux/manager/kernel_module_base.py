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
The worknode.linux.manager.kernel_module_base module provides a class
(KernelModuleManager) that manages all kernel module-related activities.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_component_manager
import framework

class KernelModuleManager(worknode.worknode_component_manager.WorkNodeComponentManager):
    """
    KernelModuleManager is an object that manages all kernel module-related
    activities. It acts as a container for kernel module-related commands as
    well as being a unified place to request abstracted kernel module
    information from.

    """
    def __init__(self, parent):
        super(KernelModuleManager, self).__init__(parent = parent)
        self.__kernel_modules = {}

    def _clear_cached_modules(self):
        for module in self.__kernel_modules.values():
            self._remove_kernel_module_object(module_object = module)
        self.__kernel_modules = {}

    def _remove_kernel_module_object(self, module_object):
        module_name = module_object.get_name()
        module = self.__kernel_modules[module_name]
        del self.__kernel_modules[module_name]
        module._delete()

    def _add_kernel_module_object(self, module_object):
        module_name = module_object.get_name()
        self.__kernel_modules[module_name] = module_object

    def get_kernel_module(self, module_name):
        """
        Get the kernel module object requested.

        Keyword arguments:
        module_name - Name of the module.

        Return value:
        Object representing the kernel module requested.

        """
        if module_name not in self.__kernel_modules:
            self.refresh_module_list()
            if module_name not in self.__kernel_modules:
                raise Exception(
                    "Unable to locate a kernel module named {0}".format(
                        module_name
                    )
                )
        return self.__kernel_modules[module_name]

    def refresh_module_list(self, preferred_command = None):
        """
        Refresh the cached list of kernel module objects.

        """
        raise NotImplementedError

    def get_all_kernel_modules(self):
        """
        Get a list of all the cached kernel module objects.

        Return value:
        List of cached kernel module objects.

        """
        if len(self.__kernel_modules) == 0:
            self.refresh_module_list()
        return list(self.__kernel_modules.values())

    def insert_kernel_module(self, module_name, preferred_command = None):
        """
        Attempt to insert the indicated kernel module.

        Keyword arguments:
        module_name - Name of the module.
        preferred_command - Command to use when inserting the kernel module.

        Return value:
        Object representing the kernel module being inserted.

        """
        raise NotImplementedError

class KernelModule(framework.Framework):
    """
    Class that represents a kernel module.

    """
    def __init__(self, name, parent):
        super(KernelModule, self).__init__()
        self.__parent = parent
        self.__name = name
        self.__used_by = []
        self.__using = []

    def _get_parent(self):
        return self.__parent

    def _get_kernel_module_manager(self):
        return self._get_parent()

    def _add_module_using_this(self, module):
        if module not in self.__used_by:
            self.__used_by.append(module)

    def _remove_module_using_this(self, module):
        if self.__used_by is not None:
            self.__used_by.remove(module)

    def _remove_using_module(self, module):
        if self.__using is not None:
            self.__using.remove(module)

    def _add_using_module(self, module):
        if module not in self.__using:
            self.__using.append(module)

    def _delete(self):
        for module in self.__using:
            module._remove_module_using_this(module = self)
        self.__using = None
        for module in self.__used_by:
            module._remove_using_module(module = self)
        self.__used_by = None
        self.__kernel_module_manager = None
        del self

    def get_name(self):
        """
        Get the name of the kernel module.

        Return value:
        Name of the kernel module.

        """
        return self.__name

    def remove(self, smart_remove = True, preferred_command = None):
        """
        Remove the module from the kernel.

        Keyword arguments:
        preferred_command - Command to use when removing the kernel module.

        """
        raise NotImplementedError

    def get_modules_using_this(self):
        """
        Get a list of KernelModule objects that are using this kernel module.

        Return value:
        List of KernelModule objects.

        """
        return self.__used_by
