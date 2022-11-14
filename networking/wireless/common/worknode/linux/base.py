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
The worknode.linux.base module provides a standard base class (LinuxWorkNode)
for all Linux work node classes to inherit from.

"""

__author__ = 'Ken Benoit'

import worknode.base

class LinuxWorkNode(worknode.base.WorkNodeBase):
    """
    LinuxWorkNode is a standard base class for more specific Linux work node
    classes to inherit from.

    """
    def __init__(self):
        super(LinuxWorkNode, self).__init__()
        self.__major_version = None
        self.__minor_version = None
        self.__hostname = None
        self.__dnsdomainname = None

    def _set_major_version(self, version_number):
        if type(version_number) is not int:
            raise TypeError("version_number needs to be an integer")
        self.__major_version = version_number

    def _set_minor_version(self, version_number):
        if type(version_number) is not int:
            raise TypeError("version_number needs to be an integer")
        self.__minor_version = version_number

    def _set_hostname(self, hostname):
        if type(hostname) is not str:
            raise TypeError("hostname needs to be a string")
        self.__hostname = hostname

    def _set_dnsdomainname(self, dnsdomainname):
        if type(dnsdomainname) is not str:
            raise TypeError("dnsdomainname needs to be a string")
        self.__dnsdomainname = dnsdomainname

    def get_major_version(self):
        """
        Get the major version number of the OS.

        Return value:
        Integer value of the major version number.

        """
        return self.__major_version

    def get_minor_version(self):
        """
        Get the minor version number of the OS.

        Return value:
        Integer value of the minor version number.

        """
        return self.__minor_version

    def get_hostname(self):
        """
        Get the hostname of the work node.

        Return value:
        String value of the work node's hostname.

        """
        return self.__hostname

    def get_dns_domain_name(self):
        """
        Get the DNS domain name of the work node.

        Return value:
        String value of the work node's DNS domain name.

        """
        return self.__dnsdomainname

    def get_network_component_manager(self):
        """
        Get the network component manager for the work node.

        Return value:
        WorkNodeComponentManager object for the network component.

        """
        return self._get_component_manager(component_name = 'network')

    def get_service_component_manager(self):
        """
        Get the service component manager for the work node.

        Return value:
        WorkNodeComponentManager object for the service component.

        """
        return self._get_component_manager(component_name = 'service')

    def get_config_file_component_manager(self):
        """
        Get the config file component manager for the work node.

        Return value:
        WorkNodeComponentManager object for the config file component.

        """
        return self._get_component_manager(component_name = 'config_file')

    def get_kernel_module_component_manager(self):
        """
        Get the kernel module component manager for the work node.

        Return value:
        WorkNodeComponentManager object for the kernel module component.

        """
        return self._get_component_manager(component_name = 'kernel_module')

    def get_file_system_component_manager(self):
        """
        Get the file system component manager for the work node.

        Return value:
        WorkNodeComponentManager object for the file system component.

        """
        return self._get_component_manager(component_name = 'file_system')

    def get_audio_component_manager(self):
        """
        Get the audio component manager for the work node.

        Return value:
        WorkNodeComponentManager object for the audio component.

        """
        return self._get_component_manager(component_name = 'audio')

    def get_bluetooth_component_manager(self):
        """
        Get the Bluetooth component manager for the work node.

        Return value:
        WorkNodeComponentManager object for the Bluetooth component.

        """
        return self._get_component_manager(component_name = 'bluetooth')

    def get_power_component_manager(self):
        """
        Get the power component manager for the work node.

        Return value:
        WorkNodeComponentManager object for the power component.

        """
        return self._get_component_manager(component_name = 'power')

class Process(worknode.base.Process):
    def __init__(self, command):
        super(Process, self).__init__(command = command)
