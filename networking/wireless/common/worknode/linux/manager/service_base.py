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
The worknode.linux.manager.service module provides a class (ServiceManager) that
manages all service-related activities.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_component_manager
import framework
import worknode.property_manager

class ServiceManager(worknode.worknode_component_manager.WorkNodeComponentManager):
    """
    ServiceManager is an object that manages all service-related activities. It
    acts as a container for service-related commands as well as being a unified
    place to request abstracted service information from.

    """
    def __init__(self, parent):
        super(ServiceManager, self).__init__(parent = parent)
        self.__supported_services = {}

    def get_service(self, service_name):
        """
        Get the service object requested.

        Keyword arguments:
        service_name - Name of the service.

        Return value:
        Object representing the service requested.

        """
        return self.__supported_services[service_name]

    def _add_supported_service(self, service_name, service_object):
        self.__supported_services[service_name] = service_object

class Service(framework.Framework):
    """
    Class that represents a service that is running or can run on the work node.

    """
    def __init__(self, parent):
        super(Service, self).__init__()
        self.__parent = parent
        self.__name = None

    def _get_parent(self):
        return self.__parent

    def _get_service_manager(self):
        return self._get_parent()

    def _set_service_name(self, name):
        if type(name) is not str:
            raise TypeError
        self.__name = name

    def _get_service_name(self):
        if self.__name is None:
            raise NameError
        return self.__name

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent})'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
        )
