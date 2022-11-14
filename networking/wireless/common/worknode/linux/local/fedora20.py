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
The worknode.linux.local.fedora20 module provides a class
(LocalFedora20WorkNode) that represents a local Fedora 20 machine.

"""

__author__ = 'Ken Benoit'

import worknode.linux.local_base
import worknode.linux.util.service

class LocalFedora20WorkNode(worknode.linux.local_base.LocalLinuxWorkNode):
    """
    LocalFedora20WorkNode represents a local Fedora 20 machine.

    """
    def __init__(self):
        super(LocalFedora20WorkNode, self).__init__()
        self.__configure_component_managers()
        self._set_major_version(version_number = 20)
        self._set_minor_version(version_number = 0)

    def __configure_component_managers(self):
        self._add_component_manager(
            component_name = 'network',
            manager_class = 'NetworkManager',
            manager_module = 'worknode.linux.manager.fedora20.network',
        )
        self._add_component_manager(
            component_name = 'service',
            manager_class = 'ServiceManager',
            manager_module = 'worknode.linux.manager.fedora20.service',
        )
        self._add_component_manager(
            component_name = 'config_file',
            manager_class = 'ConfigFileManager',
            manager_module = 'worknode.linux.manager.fedora20.config_file',
        )
        self._add_component_manager(
            component_name = 'kernel_module',
            manager_class = 'KernelModuleManager',
            manager_module = 'worknode.linux.manager.fedora20.kernel_module',
        )
        self._add_component_manager(
            component_name = 'file_system',
            manager_class = 'FileSystemManager',
            manager_module = 'worknode.linux.manager.fedora20.file_system',
        )
        self._add_component_manager(
            component_name = 'audio',
            manager_class = 'AudioManager',
            manager_module = 'worknode.linux.manager.fedora20.audio',
        )
        self.__configure_service_component_manager()

    def get_hostname(self):
        """
        Get the hostname of the work node.

        Return value:
        String value of the work node's hostname.

        """
        if super(LocalFedora20WorkNode, self).get_hostname() == None:
            output = self.run_command(command = 'hostname')
            output_string = ''.join(output)
            self._set_hostname(hostname = output_string.strip())
        return super(LocalFedora20WorkNode, self).get_hostname()

    def get_dns_domain_name(self):
        """
        Get the DNS domain name of the work node.

        Return value:
        String value of the work node's DNS domain name.

        """
        if super(LocalFedora20WorkNode, self).get_dns_domain_name() == None:
            output = self.run_command(command = 'dnsdomainname')
            output_string = ''.join(output)
            self._set_dnsdomainname(dnsdomainname = output_string.strip())
        return super(LocalFedora20WorkNode, self).get_dns_domain_name()

    def __configure_service_component_manager(self):
        service_manager = self.get_service_component_manager()
        # Configure service
        service = service_manager.add_command(
            command_name = 'service',
            command_object = worknode.linux.util.service.service(
                work_node = self,
            ),
        )
