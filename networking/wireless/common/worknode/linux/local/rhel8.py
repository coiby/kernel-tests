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
The worknode.linux.local.rhel8 module provides a class (LocalRHEL8WorkNode) that
represents a local Red Hat Enterprise Linux 8.x machine.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.local_base
import worknode.linux.util.rhel8.systemctl

class LocalRHEL8WorkNode(worknode.linux.local_base.LocalLinuxWorkNode):
    """
    LocalRHEL8WorkNode represents a local Red Hat Enterprise Linux 8.x machine.

    """
    def __init__(self):
        super(LocalRHEL8WorkNode, self).__init__()
        self.__configure_component_managers()
        self._set_major_version(version_number = 8)

    def __configure_component_managers(self):
        self._add_component_manager(
            component_name = 'network',
            manager_class = 'NetworkManager',
            manager_module = 'worknode.linux.manager.rhel8.network',
        )
        self._add_component_manager(
            component_name = 'service',
            manager_class = 'ServiceManager',
            manager_module = 'worknode.linux.manager.rhel8.service',
        )
        self._add_component_manager(
            component_name = 'config_file',
            manager_class = 'ConfigFileManager',
            manager_module = 'worknode.linux.manager.rhel8.config_file',
        )
        self._add_component_manager(
            component_name = 'kernel_module',
            manager_class = 'KernelModuleManager',
            manager_module = 'worknode.linux.manager.rhel8.kernel_module',
        )
        self._add_component_manager(
            component_name = 'file_system',
            manager_class = 'FileSystemManager',
            manager_module = 'worknode.linux.manager.rhel8.file_system',
        )
        self._add_component_manager(
            component_name = 'audio',
            manager_class = 'AudioManager',
            manager_module = 'worknode.linux.manager.rhel8.audio',
        )
        self._add_component_manager(
            component_name = 'bluetooth',
            manager_class = 'BluetoothManager',
            manager_module = 'worknode.linux.manager.rhel8.bluetooth',
        )
        self._add_component_manager(
            component_name = 'power',
            manager_class = 'PowerManager',
            manager_module = 'worknode.linux.manager.rhel8.power',
        )
        self.__configure_service_component_manager()

    def __configure_service_component_manager(self):
        service_manager = self.get_service_component_manager()
        # Configure systemctl
        systemctl = service_manager.add_command(
            command_name = 'systemctl',
            command_object = worknode.linux.util.rhel8.systemctl.systemctl(
                work_node = self,
            ),
        )

    def get_hostname(self):
        """
        Get the hostname of the work node.

        Return value:
        String value of the work node's hostname.

        """
        if super(LocalRHEL8WorkNode, self).get_hostname() == None:
            output = self.run_command(command = 'hostname')
            output_string = ''.join(output)
            self._set_hostname(hostname = output_string.strip())
        return super(LocalRHEL8WorkNode, self).get_hostname()

    def get_dns_domain_name(self):
        """
        Get the DNS domain name of the work node.

        Return value:
        String value of the work node's DNS domain name.

        """
        if super(LocalRHEL8WorkNode, self).get_dns_domain_name() == None:
            output = self.run_command(command = 'dnsdomainname')
            output_string = ''.join(output)
            self._set_dnsdomainname(dnsdomainname = output_string.strip())
        return super(LocalRHEL8WorkNode, self).get_dns_domain_name()

    def get_minor_version(self):
        """
        Get the minor version number of the OS.

        Return value:
        Integer value of the minor version number.

        """
        if super(LocalRHEL8WorkNode, self).get_minor_version() == None:
            commands_to_try = ['cat /etc/redhat-release', 'cat /etc/issue']
            for command in commands_to_try:
                output = self.run_command(command = command)
                output_string = ''.join(output)
                match = re.search('8\.(?P<minor_version>\d+)\s+', output_string)
                if match:
                    self._set_minor_version(
                        version_number = int(match.group('minor_version')),
                    )
                    break
        return super(LocalRHEL8WorkNode, self).get_minor_version()

    def start_process(self, command):
        """
        Run the command provided and return the process object.

        Keyword arguments:
        command - Command string.

        Return value:
        subprocess.Popen object.

        """
        self.get_logger().debug("Running command: {0}".format(command))
        # Launch the process
        process = Process(command)
        self.get_logger().debug(
            "Process pid {0}".format(process.get_process_id())
        )
        return process

class Process(worknode.linux.local_base.Process):
    def get_output(self, all = False, suppress_logging = False):
        """
        Get a list of lines of output from the process.

        Keyword arguments:
        all - If True, get all lines of output from the process. If the process
              is still running then this call will block until the process has
              finished. Otherwise this call will get output one line for every
              call made to this method.

        Return value:
        List of lines of output from the process.

        """
        output = super(Process, self).get_output(
            all = all,
            suppress_logging = suppress_logging
        )
        reformatted_output = []
        for line in output:
            reformatted_output.append(line.decode('UTF-8'))
        return reformatted_output
