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
The worknode.linux.manager.software_management_base module provides a class
(SoftwareManager) that manages all software management-related activities.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_component_manager
import framework
import worknode.property_manager
from worknode.exception.worknode_executable import *

class SoftwareManager(worknode.worknode_component_manager.WorkNodeComponentManager):
    """
    SoftwareManager is an object that manages all software management-related
    activities. It acts as a container for software management-related commands
    as well as being a unified place to request abstracted software information
    from.

    """
    def __init__(self, parent):
        super(SoftwareManager, self).__init__(parent = parent)
        self.__software_packages = {}
        self.__software_package_class = None
        self.__initialize_property_manager()
        self._set_software_package_class(class_object = SoftwarePackage)

    def __initialize_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'package_name')

    def _set_software_package_class(self, class_object):
        self.__software_package_class = class_object

    def _get_software_package_class(self, class_object):
        return self.__software_package_class

    def __clear_package_list(self):
        for package in list(self.__software_packages.values()):
            del package
        for key in list(self.__software_packages.keys()):
            del self.__software_packages[key]

    def __create_package(self, package_name):
        stored_class = self._get_software_package_class()
        package = stored_class(
            parent = self,
            name = package_name,
        )
        self.__add_package(package_object = package)

    def __add_package(self, package_object):
        self.__software_packages[package_object.get_name()] = package_object

    def get_property_manager(self):
        """
        Get the property manager.

        Return value:
        PropertyManager object.

        """
        return self.__property_manager

    def refresh_software_package_list(self):
        """
        Refresh the cached list of SoftwarePackage objects.

        """
        self.get_property_manager().refresh_properties()
        package_names = self.get_property_manager().get_property_value(
            property_name = 'package_name',
        )
        self.__clear_package_list()
        for name in package_names:
            self.__create_package(package_name = name)

    def get_software_packages(self, refresh_list = False):
        """
        Get a list of SoftwarePackage objects.

        Keyword arguments:
        refresh_list - If True force a refresh of the cached SoftwarePackage
                       objects.

        Return value:
        List of SoftwarePackage objects.

        """
        packages = []
        if refresh_list:
            self.refresh_software_package_list()
        elif self.__software_packages == {}:
            self.refresh_software_package_list()
        for package in self.__software_packages.values():
            packages.append(package)
        return packages

    def get_software_package(self, package_name):
        """
        Get a specific SoftwarePackage object.

        Keyword arguments:
        package_name - Name of the software package.

        Return value:
        SoftwarePackage object.

        """
        if package_name not in self.__software_packages:
            self.refresh_software_package_list()
            if package_name not in self.__software_packages:
                raise KeyError(
                    "Unable to locate software package {0}".format(package_name)
                )
        return self.__software_packages[package_name]

class SoftwarePackage(framework.Framework):
    """
    SoftwarePackage is an object that represents a package that can be installed
    through the package manager on the work node.

    """
    def __init__(self, parent, name):
        super(SoftwarePackage, self).__init__()
        self.__parent = parent
        self.__property_manager = worknode.property_manager.PropertyManager(
            work_node = parent,
        )
        self.__initialize_property_manager()
        self.get_property_manager().set_property(
            property_name = 'name',
            property_value = name,
        )

    def __initialize_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'name')
        property_manager.initialize_property(property_name = 'version')
        property_manager.initialize_property(property_name = 'installed')

    def _get_parent(self):
        return self.__parent

    def _get_manager(self):
        return self._get_parent()

    def _get_work_node(self):
        return self._get_manager()._get_work_node()

    def get_property_manager(self):
        """
        Get the property manager.

        Return value:
        PropertyManager object.

        """
        return self.__property_manager

    def get_name(self):
        """
        Get the name of the package.

        Return value:
        String representation of name of the package.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'name',
        )

    def get_version(self):
        """
        Get the version of the package.

        Return value:
        String representation of version of the package.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'version',
        )

    def is_installed(self):
        """
        Check if the package is currently installed on the work node.

        Return value:
        True if the package is currently installed, False otherwise.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'installed',
        )

    def remove(self):
        """
        Abstract: Remove the package from the work node.

        """
        raise NotImplementedError

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent}, name = {name})'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
            name = self.get_name(),
        )
