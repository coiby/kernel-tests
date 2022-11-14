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
The functional.connection.cleanup.test module provides a class (Test) that
cleans up an already configured wireless connection.

"""

__author__ = 'Ken Benoit'

import time

import functional.connection.functional_connection_base
from base.exception.test import *
from functional.connection.functional_connection_constants import *
from worknode.linux.manager.exception.file_system import *

class Test(functional.connection.functional_connection_base.FunctionalConnectionBaseTest):
    """
    Test performs cleanup of a functional wireless connection test.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.test_preferred_command = None
        self.test_network_name = 'test_network'
        self.preconfigured_setups_file = 'preconfigured_setups.json'

        self.set_test_name(name = '/kernel/wireless_tests/functional/connection/cleanup')
        self.set_test_author(name = 'Ken Benoit', email = 'kbenoit@redhat.com')
        self.set_test_description(description = 'Cleanup a wireless connection.')

        self.add_command_line_option(
            '--preferredCommand',
            dest = 'preferred_command',
            action = 'store',
            default = None,
            help = 'command to use for configuring the wireless connection',
        )

        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.choose_test_wireless_interface,
            test_step_description = 'Choose which wireless interface to use and describe it',
        )
        self.add_test_step(
            test_step = self.bring_down_wireless_interfaces,
            test_step_description = 'Disable the wireless interface',
        )
        self.add_test_step(
            test_step = self.locate_certificates,
            test_step_description = 'Locate any downloaded certificates',
        )
        self.add_test_step(
            test_step = self.delete_certificates,
            test_step_description = 'Delete the downloaded certificates',
        )

    def bring_down_wireless_interfaces(self):
        """
        Bring all of the wireless network interfaces down.

        """
        self.test_preferred_command = self.get_command_line_option_value(
            dest = 'preferred_command',
        )
        delete_connection_arguments = {}
        if self.test_preferred_command is not None:
            delete_connection_arguments['preferred_command'] = self.test_preferred_command
        delete_connection_arguments['network_name'] = self.test_network_name
        delete_connection_arguments['wpa_supplicant_conf_backup_name'] = WPA_SUPPLICANT_CONF_BACKUP_FILE
        delete_connection_arguments['wpa_supplicant_sysconfig_backup_name'] = WPA_SUPPLICANT_SYSCONFIG_BACKUP_FILE
        network_manager = self.work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()
        for interface in interfaces:
            interface.disable(preferred_command = 'ip')
        self.test_interface.delete_wireless_connection(
            **delete_connection_arguments
        )
        time.sleep(10)

    def locate_certificates(self):
        """
        Locate any downloaded certificate files so that they can be deleted
        later.

        """
        ca_cert_local_path = LOCAL_CERT_DIR + CA_CERT_LOCAL_FILE
        client_cert_local_path = LOCAL_CERT_DIR + CLIENT_CERT_LOCAL_FILE
        private_key_local_path = LOCAL_CERT_DIR + PRIVATE_KEY_LOCAL_FILE
        # Locate the CA certificate
        try:
            self.local_ca_cert = self.work_node.get_file_system_component_manager().get_file(
                file_path = ca_cert_local_path,
            )
        except FileException:
            self.get_logger().debug(
                "Unable to find file {0}".format(ca_cert_local_path)
            )
        # Locate the client certificate
        try:
            self.local_client_cert = self.work_node.get_file_system_component_manager().get_file(
                file_path = client_cert_local_path,
            )
        except FileException:
            self.get_logger().debug(
                "Unable to find file {0}".format(client_cert_local_path)
            )
        # Locate the private key
        try:
            self.local_private_key = self.work_node.get_file_system_component_manager().get_file(
                file_path = private_key_local_path,
            )
        except FileException:
            self.get_logger().debug(
                "Unable to find file {0}".format(private_key_local_path)
            )

if __name__ == '__main__':
    exit(Test().run_test())
