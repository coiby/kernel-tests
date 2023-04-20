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
The functional.connection.wpa_supplicant.connection_base module provides a class
(ConnectionBaseTest) provides the base test steps for all wpa_supplicant
connection-based tests.

"""

__author__ = 'Ken Benoit'

import re
import time

import functional.connection.functional_connection_base
from functional.connection.functional_connection_constants import *
from base.exception.test import *

class ConnectionBaseTest(functional.connection.functional_connection_base.FunctionalConnectionBaseTest):
    """
    ConnectionBaseTest provides the base test steps for all connection-based
    wpa_supplicant tests.

    """
    def __init__(self):
        super(ConnectionBaseTest, self).__init__()
        self.test_ssid = None
        self.test_psk = None
        self.test_wep_key0 = None
        self.test_key_management_type = None
        self.test_hidden = False
        self.test_eap = None
        self.test_identity = None
        self.test_password = None
        self.test_ca_cert = None
        self.test_client_cert = None
        self.test_private_key = None
        self.test_private_key_password = None
        self.test_phase2_autheap = None
        self.test_auth_alg = None
        self.test_network_name = 'test_network'

        self.add_command_line_option(
            '-p',
            '--pingAddress',
            dest = 'ping_address',
            action = 'store',
            default = None,
            help = 'IP address to ping to verify connection. if not supplied '
                + 'then "{0}" will be used'.format(PING_ADDRESS),
        )

        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.choose_test_wireless_interface,
            test_step_description = 'Choose which wireless interface to use and describe it',
        )
        self.add_test_step(
            test_step = self.get_wired_interfaces,
        )
        self.add_test_step(
            test_step = self.bring_down_wired_interfaces,
            test_step_description = 'Disable the wired network interfaces',
            rollback_step = self.bring_up_wired_interfaces,
            rollback_step_description = 'Enable the wired network interfaces',
        )
        self.add_test_step(
            test_step = self.configure_test_wireless_interface,
            test_step_description = 'Configure the test wireless interface',
            rollback_step = self.bring_down_wireless_interfaces,
            rollback_step_description = 'Disable the wireless interface',
        )
        self.add_test_step(
            test_step = self.ping_ip_address,
            test_step_description = 'Ping an IP address to verify connection',
        )
        self.add_test_step(
            test_step = self.bring_down_wireless_interfaces,
            test_step_description = 'Disable the wireless interface',
        )
        self.add_test_step(
            test_step = self.bring_up_wired_interfaces,
            test_step_description = 'Enable the wired network interfaces',
            rollback_step = self.restart_networking,
            rollback_step_description = 'Restart the networking services',
        )

    def set_ssid(self, ssid):
        """
        Set the SSID of the wireless network to connect to.

        Keyword arguments:
        ssid - SSID of the wireless network.

        """
        self.test_ssid = ssid

    def set_psk(self, psk):
        """
        Set the pre-shared key of the wireless network being connected to.

        Keyword arguments:
        psk - Pre-shared key used to connect to the wireless network.

        """
        self.test_psk = psk

    def set_wep_key0(self, key):
        """
        Set the WEP key of the wireless network being connected to.

        Keyword arguments:
        key - WEP key used to connect to the wireless network.

        """
        self.test_wep_key0 = key

    def set_key_management_type(self, management_type):
        """
        Set the type of key management used for the wireless network.

        Keyword arguments:
        management_type - Type of key management to use.

        """
        self.test_key_management_type = management_type

    def set_hidden(self, hidden):
        """
        Set if the wireless network being connected to does not have its SSID
        broadcast.

        Keyword arguments:
        hidden - If True then the wireless network is treated as hidden.

        """
        self.test_hidden = hidden

    def set_eap(self, eap):
        """
        Set the EAP authentication type.

        Keyword arguments:
        eap - EAP authentication type.

        """
        self.test_eap = eap

    def set_phase2_autheap(self, autheap):
        """
        Set the allowed phase 2 EAP authentication method.

        Keyword arguments:
        autheap - Allowed phase 2 EAP authentication method.

        """
        self.test_phase2_autheap = autheap

    def set_auth_alg(self, alg):
        """
        Set the authentication algorithm.

        Keyword arguments:
        alg - Authentication algorithm.

        """
        self.test_auth_alg = alg

    def set_identity(self, identity):
        """
        Set the identity string to authenticate with.

        Keyword arguments:
        identity - Identity string.

        """
        self.test_identity = identity

    def set_password(self, password):
        """
        Set the password string to authenticate with.

        Keyword arguments:
        password - Password string.

        """
        self.test_password = password

    def set_ca_cert(self, path):
        """
        Set the path to the CA certificate file.

        Keyword arguments:
        path - Path to the CA certificate file.

        """
        self.test_ca_cert = path

    def set_client_cert(self, path):
        """
        Set the path to the client certificate file.

        Keyword arguments:
        path - Path to the client certificate file.

        """
        self.test_client_cert = path

    def set_private_key(self, path):
        """
        Set the path to the private key file.

        Keyword arguments:
        path - Path to the private key file.

        """
        self.test_private_key = path

    def set_private_key_password(self, password):
        """
        Set the password to decrypt the private key file.

        Keyword arguments:
        password - Password to decrypt the private key file.

        """
        self.test_private_key_password = password

    def get_wired_interfaces(self):
        """
        Get the list of wired interfaces.

        """
        network_manager = self.work_node.get_network_component_manager()
        self.wired_interfaces = network_manager.get_wired_interfaces()

    def ping_ip_address(self):
        """
        Ping an IP address to verify we have a connection.

        """
        test_address = None
        ping_address = self.get_command_line_option_value(
            dest = 'ping_address',
        )
        if ping_address == None:
            test_address = PING_ADDRESS
        else:
            test_address = ping_address
        if not self.test_interface.is_destination_reachable(
            destination = test_address,
            timeout = 30,
            minimum_success_count = 2,
        ):
            raise TestFailure(
                "Unable to verify the connection by contacting {0}".format(
                    test_address
                )
            )

    def bring_down_wired_interfaces(self):
        """
        Bring all of the wired network interfaces down.

        """
        for interface in self.wired_interfaces:
            interface.disable()

    def bring_up_wired_interfaces(self):
        """
        Bring all of the wired network interfaces back up.

        """
        for interface in self.wired_interfaces:
            interface.enable()

    def restart_networking(self):
        """
        Restart the networking services and re-enable the wired interfaces.

        """
        network_manager = self.work_node.get_network_component_manager()
        network_manager.restart_network_services()

    def bring_down_wireless_interfaces(self):
        """
        Bring all of the wireless network interfaces down.

        """
        network_manager = self.work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()
        for interface in interfaces:
            interface.disable(preferred_command = 'ip')
        self.test_interface.delete_wireless_connection(
            network_name = self.test_network_name,
            preferred_command = 'wpa_supplicant',
        )
        time.sleep(10)

    def configure_test_wireless_interface(self):
        """
        Configure the wireless test interface for a wireless network.

        """
        if self.is_ca_cert_required():
            if self.test_ca_cert is None:
                self.test_ca_cert = self.get_local_ca_cert_file()
        if self.is_client_cert_required():
            if self.test_client_cert is None:
                self.test_client_cert = self.get_local_client_cert_file()
        if self.is_private_key_required():
            if self.test_private_key is None:
                self.test_private_key = self.get_local_private_key_file()
        self.test_interface.configure_wireless_connection(
            ssid = self.test_ssid,
            psk = self.test_psk,
            wep_key0 = self.test_wep_key0,
            key_management = self.test_key_management_type,
            network_name = self.test_network_name,
            hidden = self.test_hidden,
            eap = self.test_eap,
            identity = self.test_identity,
            password = self.test_password,
            ca_cert = self.test_ca_cert,
            client_cert = self.test_client_cert,
            private_key = self.test_private_key,
            private_key_password = self.test_private_key_password,
            phase2_autheap = self.test_phase2_autheap,
            auth_alg = self.test_auth_alg,
            preferred_command = 'wpa_supplicant',
        )

    def replace_test_step_description(self, pattern, new_description):
        """
        Replace the test step description of all test step descriptions matching
        the pattern supplied with the new description.

        Keyword arguments:
        pattern - Regular expression pattern to search for.
        new_description - New description to associate with the test steps.

        """
        test_step_list = self.get_test_step_list()
        for step_number in range(len(test_step_list)):
            description = test_step_list.get_test_step_description(
                step_number = step_number,
            )
            if description is None:
                continue
            if re.search(pattern, description):
                test_step_list.set_test_step_description(
                    step_number = step_number,
                    description = new_description,
                )
