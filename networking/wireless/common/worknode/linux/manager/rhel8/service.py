#!/usr/bin/python
# Copyright (c) 2018 Red Hat, Inc. All rights reserved. This copyrighted material
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
The worknode.linux.manager.rhel8.service module provides a class
(ServiceManager) that manages all service-related activities.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.manager.service_base
import worknode.linux.util.rhel8.systemctl

class ServiceManager(worknode.linux.manager.service_base.ServiceManager):
    """
    ServiceManager is an object that manages all service-related activities. It
    acts as a container for service-related commands as well as being a unified
    place to request abstracted service information from.

    """
    def __init__(self, parent):
        super(ServiceManager, self).__init__(parent = parent)
        self._add_supported_service(
            service_name = 'NetworkManager',
            service_object = NetworkManager(parent = self),
        )
        self._add_supported_service(
            service_name = 'wpa_supplicant',
            service_object = wpa_supplicant(parent = self),
        )
        self._add_supported_service(
            service_name = 'network',
            service_object = network(parent = self),
        )
        self._add_supported_service(
            service_name = 'bluetooth',
            service_object = bluetooth(parent = self),
        )

class Service(worknode.linux.manager.service_base.Service):
    def __init__(self, parent):
        super(Service, self).__init__(parent = parent)

    def start(self, preferred_command = 'systemctl'):
        """
        Start the service.

        """
        service_manager = self._get_service_manager()
        # If the command to use is systemctl
        if preferred_command == 'systemctl':
            systemctl = service_manager.get_command_object(
                command_name = 'systemctl',
            )
            service_name = self._get_service_name()
            systemctl.start(unit_name = service_name)
            if not self.is_running():
                raise Exception(
                    "Failed to start the {0} service".format(service_name)
                )
        # We have no idea what command you're trying to use
        else:
            raise Exception("Unable to find a suitable command to use")

    def stop(self, preferred_command = 'systemctl'):
        """
        Stop the service.

        """
        service_manager = self._get_service_manager()
        # If the command to use is systemctl
        if preferred_command == 'systemctl':
            systemctl = service_manager.get_command_object(
                command_name = 'systemctl',
            )
            service_name = self._get_service_name()
            systemctl.stop(unit_name = service_name)
            if self.is_running():
                raise Exception(
                    "Failed to stop the {0} service".format(service_name)
                )
        # We have no idea what command you're trying to use
        else:
            raise Exception("Unable to find a suitable command to use")

    def restart(self, preferred_command = 'systemctl'):
        """
        Restart the service.

        """
        service_manager = self._get_service_manager()
        # If the command to use is systemctl
        if preferred_command == 'systemctl':
            systemctl = service_manager.get_command_object(
                command_name = 'systemctl',
            )
            service_name = self._get_service_name()
            systemctl.restart(unit_name = service_name)
            if not self.is_running():
                raise Exception(
                    "Failed to restart the {0} service".format(service_name)
                )
        # We have no idea what command you're trying to use
        else:
            raise Exception("Unable to find a suitable command to use")

    def is_running(self, preferred_command = 'systemctl'):
        """
        Check if the service is running.

        Return value:
        True if the service is running. False otherwise.

        """
        service_manager = self._get_service_manager()
        run_status = False
        # If the command to use is systemctl
        if preferred_command == 'systemctl':
            systemctl = service_manager.get_command_object(
                command_name = 'systemctl',
            )
            service_name = self._get_service_name()
            is_running = systemctl.is_running(unit_name = service_name)
            if is_running:
                run_status = True
        # We have no idea what command you're trying to use
        else:
            raise Exception("Unable to find a suitable command to use")

        return run_status

class NetworkManager(Service):
    def __init__(self, parent):
        super(NetworkManager, self).__init__(parent = parent)
        self._set_service_name(name = 'NetworkManager')

class wpa_supplicant(Service):
    def __init__(self, parent):
        super(wpa_supplicant, self).__init__(parent = parent)
        self._set_service_name(name = 'wpa_supplicant')

class network(Service):
    def __init__(self, parent):
        super(network, self).__init__(parent = parent)
        self._set_service_name(name = 'network')

class bluetooth(Service):
    def __init__(self, parent):
        super(bluetooth, self).__init__(parent = parent)
        self._set_service_name(name = 'bluetooth')
