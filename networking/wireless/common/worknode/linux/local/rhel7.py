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
The worknode.linux.local.rhel7 module provides a class (LocalRHEL7WorkNode) that
represents a local Red Hat Enterprise Linux 7.x machine.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.local_base
import worknode.linux.util.rhel7.systemctl

class LocalRHEL7WorkNode(worknode.linux.local_base.LocalLinuxWorkNode):
    """
    LocalRHEL7WorkNode represents a local Red Hat Enterprise Linux 7.x machine.

    """
    def __init__(self):
        super(LocalRHEL7WorkNode, self).__init__()
        self.__configure_component_managers()
        self._set_major_version(version_number = 7)

    def __configure_component_managers(self):
        self._add_component_manager(
            component_name = 'network',
            manager_class = 'NetworkManager',
            manager_module = 'worknode.linux.manager.rhel7.network',
        )
        self._add_component_manager(
            component_name = 'service',
            manager_class = 'ServiceManager',
            manager_module = 'worknode.linux.manager.rhel7.service',
        )
        self._add_component_manager(
            component_name = 'config_file',
            manager_class = 'ConfigFileManager',
            manager_module = 'worknode.linux.manager.rhel7.config_file',
        )
        self._add_component_manager(
            component_name = 'kernel_module',
            manager_class = 'KernelModuleManager',
            manager_module = 'worknode.linux.manager.rhel7.kernel_module',
        )
        self._add_component_manager(
            component_name = 'file_system',
            manager_class = 'FileSystemManager',
            manager_module = 'worknode.linux.manager.rhel7.file_system',
        )
        self._add_component_manager(
            component_name = 'audio',
            manager_class = 'AudioManager',
            manager_module = 'worknode.linux.manager.rhel7.audio',
        )
        self._add_component_manager(
            component_name = 'bluetooth',
            manager_class = 'BluetoothManager',
            manager_module = 'worknode.linux.manager.rhel7.bluetooth',
        )
        self._add_component_manager(
            component_name = 'power',
            manager_class = 'PowerManager',
            manager_module = 'worknode.linux.manager.rhel7.power',
        )
        self.__configure_service_component_manager()

    def __configure_service_component_manager(self):
        service_manager = self.get_service_component_manager()
        # Configure systemctl
        systemctl = service_manager.add_command(
            command_name = 'systemctl',
            command_object = worknode.linux.util.rhel7.systemctl.systemctl(
                work_node = self,
            ),
        )

    def get_hostname(self):
        """
        Get the hostname of the work node.

        Return value:
        String value of the work node's hostname.

        """
        if super(LocalRHEL7WorkNode, self).get_hostname() == None:
            output = self.run_command(command = 'hostname')
            output_string = ''.join(output)
            self._set_hostname(hostname = output_string.strip())
        return super(LocalRHEL7WorkNode, self).get_hostname()

    def get_dns_domain_name(self):
        """
        Get the DNS domain name of the work node.

        Return value:
        String value of the work node's DNS domain name.

        """
        if super(LocalRHEL7WorkNode, self).get_dns_domain_name() == None:
            output = self.run_command(command = 'dnsdomainname')
            output_string = ''.join(output)
            self._set_dnsdomainname(dnsdomainname = output_string.strip())
        return super(LocalRHEL7WorkNode, self).get_dns_domain_name()

    def get_minor_version(self):
        """
        Get the minor version number of the OS.

        Return value:
        Integer value of the minor version number.

        """
        if super(LocalRHEL7WorkNode, self).get_minor_version() == None:
            commands_to_try = ['cat /etc/redhat-release', 'cat /etc/issue']
            for command in commands_to_try:
                output = self.run_command(command = command)
                output_string = ''.join(output)
                match = re.search('7\.(?P<minor_version>\d+)\s+', output_string)
                if match:
                    self._set_minor_version(
                        version_number = int(match.group('minor_version')),
                    )
                    break
        return super(LocalRHEL7WorkNode, self).get_minor_version()
