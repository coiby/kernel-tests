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
The functional.connection.setup.test module provides a class (Test) that sets up
a wireless network connection.

"""

__author__ = 'Ken Benoit'

import json
import time

import functional.connection.functional_connection_base
from base.exception.test import *
from functional.connection.functional_connection_constants import *
from worknode.linux.manager.exception.file_system import *

class Test(functional.connection.functional_connection_base.FunctionalConnectionBaseTest):
    """
    Test performs a functional wireless connection test.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.test_wireless_connection_settings = {
            'ssid': None,
            'key_management': None,
            'pairwise': None,
            'group': None,
            'proto': None,
            'psk': None,
            'eap': None,
            'identity': None,
            'ca_cert': None,
            'client_cert': None,
            'private_key': None,
            'private_key_password': None,
            'auth_alg': None,
            'password': None,
            'phase2_autheap': None,
            'wep_key_type': None,
            'wep_key0': None,
            'wep_key1': None,
            'wep_key2': None,
            'wep_key3': None,
            'hidden': False,
        }
        self.settings_to_custom_map = {
            'ssid': 'custom_ssid',
            'key_management': 'custom_key_management_type',
            'pairwise': 'custom_pairwise',
            'group': 'custom_group',
            'proto': 'custom_proto',
            'psk': 'custom_psk',
            'eap': 'custom_eap',
            'identity': 'custom_identity',
            'private_key_password': 'custom_private_key_password',
            'auth_alg': 'custom_auth_alg',
            'password': 'custom_password',
            'phase2_autheap': 'custom_phase2_autheap',
            'wep_key_type': 'custom_wep_key_type',
            'wep_key0': 'custom_wep_key_0',
            'wep_key1': 'custom_wep_key_1',
            'wep_key2': 'custom_wep_key_2',
            'wep_key3': 'custom_wep_key_3',
            'hidden': 'custom_hidden',
        }
        self.test_preferred_command = None
        self.test_network_name = 'test_network'
        self.preconfigured_setups_file = 'preconfigured_setups.json'

        self.set_test_name(name = '/kernel/wireless_tests/functional/connection/setup')
        self.set_test_author(name = 'Ken Benoit', email = 'kbenoit@redhat.com')
        self.set_test_description(description = 'Setup a wireless connection.')

        self.add_command_line_option(
            '--connectionPreset',
            dest = 'connection_preset',
            action = 'store',
            default = 'random',
            help = 'name of a connection preset',
        )
        self.add_command_line_option(
            '--customSSID',
            dest = 'custom_ssid',
            action = 'store',
            default = None,
            help = 'custom SSID to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customKeyManagementType',
            dest = 'custom_key_management_type',
            action = 'store',
            default = None,
            help = 'custom key management type to use for the wireless '
                + 'connection',
        )
        self.add_command_line_option(
            '--customPairwise',
            dest = 'custom_pairwise',
            action = 'store',
            default = None,
            help = 'custom pairwise encryption algorithm to use for the '
                + 'wireless connection',
        )
        self.add_command_line_option(
            '--customGroup',
            dest = 'custom_group',
            action = 'store',
            default = None,
            help = 'custom group encrpytion algorithm to use for the wireless '
                + 'connection',
        )
        self.add_command_line_option(
            '--customProto',
            dest = 'custom_proto',
            action = 'store',
            default = None,
            help = 'custom WPA protocol to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customPSK',
            dest = 'custom_psk',
            action = 'store',
            default = None,
            help = 'custom pre-shared key to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customEAP',
            dest = 'custom_eap',
            action = 'store',
            default = None,
            help = 'custom EAP method to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customIdentity',
            dest = 'custom_identity',
            action = 'store',
            default = None,
            help = 'custom identity string to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customPrivateKeyPassword',
            dest = 'custom_private_key_password',
            action = 'store',
            default = None,
            help = 'custom password used to decrypt the private key to use for '
                + 'the wireless connection',
        )
        self.add_command_line_option(
            '--customAuthAlg',
            dest = 'custom_auth_alg',
            action = 'store',
            default = None,
            help = 'custom authentication algorithm for WEP to use for the '
                + 'wireless connection',
        )
        self.add_command_line_option(
            '--customPassword',
            dest = 'custom_password',
            action = 'store',
            default = None,
            help = 'custom password for authentication to use for the wireless '
                + 'connection',
        )
        self.add_command_line_option(
            '--customPhase2AuthEAP',
            dest = 'custom_phase2_autheap',
            action = 'store',
            default = None,
            help = 'custom allowed phase 2 inner EAP-based authentication '
                + 'methods to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customWEPKeyType',
            dest = 'custom_wep_key_type',
            action = 'store',
            default = None,
            help = 'custom WEP key type (1 for hexadecimal or ASCII, 2 for MD5 '
                + 'hashed passphrase) to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customWEPKey0',
            dest = 'custom_wep_key_0',
            action = 'store',
            default = None,
            help = 'custom index 0 WEP key to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customWEPKey1',
            dest = 'custom_wep_key_1',
            action = 'store',
            default = None,
            help = 'custom index 1 WEP key to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customWEPKey2',
            dest = 'custom_wep_key_2',
            action = 'store',
            default = None,
            help = 'custom index 2 WEP key to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customWEPKey3',
            dest = 'custom_wep_key_3',
            action = 'store',
            default = None,
            help = 'custom index 3 WEP key to use for the wireless connection',
        )
        self.add_command_line_option(
            '--customHiddenNetwork',
            dest = 'custom_hidden',
            action = 'store_true',
            default = None,
            help = 'custom setting to indicate the wireless connection is '
                + 'hidden (not broadcasting SSID)',
        )
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
            test_step = self.set_additional_networking_configuration,
        )
        self.add_test_step(
            test_step = self.choose_test_wireless_interface,
            test_step_description = 'Choose which wireless interface to use and describe it',
        )
        self.add_test_step(
            test_step = self.determine_connection_information,
            test_step_description = 'Determine the connection information to use',
        )
        self.add_test_step(
            test_step = self.download_certificates,
            test_step_description = 'Download the certificates needed for authentication',
            rollback_step = self.delete_certificates,
            rollback_step_description = 'Delete the downloaded certificates',
        )
        self.add_test_step(
            test_step = self.configure_test_wireless_interface,
            test_step_description = 'Configure the test wireless interface',
            rollback_step = self.bring_down_wireless_interfaces,
            rollback_step_description = 'Disable the wireless interface',
        )

    def determine_connection_information(self):
        """
        Determine the connection information to use when configuring the
        wireless connection.

        """
        self.test_preferred_command = self.get_command_line_option_value(
            dest = 'preferred_command',
        )
        connection_preset = self.get_command_line_option_value(
            dest = 'connection_preset',
        )
        wireless_connection_settings = {}
        # Check if this is supposed to be a custom connection
        if connection_preset != 'custom':
            preconfigured_setups_file = open(self.preconfigured_setups_file)
            preconfigured_setups = json.load(preconfigured_setups_file)
            preconfigured_setups_file.close()
            # Pick a random connection
            if connection_preset == 'random':
                settings = self.get_random_module().choice(
                    list(preconfigured_setups.values())
                )
                for key in settings.keys():
                    if key == 'ca_cert_url':
                        self.require_ca_cert(required = True)
                        self.set_ca_cert_url(url = settings[key])
                    elif key == 'client_cert_url':
                        self.require_client_cert(required = True)
                        self.set_client_cert_url(url = settings[key])
                    elif key == 'private_key_url':
                        self.require_private_key(required = True)
                        self.set_private_key_url(url = settings[key])
                    else:
                        wireless_connection_settings[key] = settings[key]
            # Use the preset connection specified
            else:
                if connection_preset not in preconfigured_setups:
                    raise TestFailure(
                        "Unable to locate a preset for '{0}'".format(
                            connection_preset,
                        )
                    )
                settings = preconfigured_setups[connection_preset]
                for key in settings.keys():
                    if key == 'ca_cert_url':
                        self.require_ca_cert(required = True)
                        self.set_ca_cert_url(url = settings[key])
                    elif key == 'client_cert_url':
                        self.require_client_cert(required = True)
                        self.set_client_cert_url(url = settings[key])
                    elif key == 'private_key_url':
                        self.require_private_key(required = True)
                        self.set_private_key_url(url = settings[key])
                    else:
                        wireless_connection_settings[key] = settings[key]
        for key in self.test_wireless_connection_settings.keys():
            if key in self.settings_to_custom_map:
                custom_arg_name = self.settings_to_custom_map[key]
                custom_arg_value = self.get_command_line_option_value(
                    dest = custom_arg_name,
                )
                if custom_arg_value is not None:
                    wireless_connection_settings[key] = custom_arg_value
        for key in wireless_connection_settings.keys():
            self.test_wireless_connection_settings[key] = \
                wireless_connection_settings[key]
        self.get_logger().debug(
            "{0}".format(self.test_wireless_connection_settings)
        )

    def get_wired_interfaces(self):
        """
        Get the list of wired interfaces.

        """
        network_manager = self.work_node.get_network_component_manager()
        self.wired_interfaces = network_manager.get_wired_interfaces()

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
        delete_connection_arguments = {}
        if self.test_preferred_command is not None:
            delete_connection_arguments['preferred_command'] = self.test_preferred_command
        delete_connection_arguments['network_name'] = self.test_network_name
        network_manager = self.work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()
        for interface in interfaces:
            interface.disable(preferred_command = 'ip')
        self.test_interface.delete_wireless_connection(
            **delete_connection_arguments
        )
        time.sleep(10)

    def configure_test_wireless_interface(self):
        """
        Configure the wireless test interface for a wireless network.

        """
        wireless_connection_settings = {}
        for key in self.test_wireless_connection_settings.keys():
            wireless_connection_settings[key] = \
                self.test_wireless_connection_settings[key]
        if self.test_preferred_command is not None:
            wireless_connection_settings['preferred_command'] = \
                self.test_preferred_command
        wireless_connection_settings['ca_cert'] = self.local_ca_cert
        wireless_connection_settings['client_cert'] = self.local_client_cert
        wireless_connection_settings['private_key'] = self.local_private_key
        wireless_connection_settings['network_name'] = self.test_network_name
        wireless_connection_settings['wpa_supplicant_conf_backup_name'] = \
            WPA_SUPPLICANT_CONF_BACKUP_FILE
        wireless_connection_settings['wpa_supplicant_sysconfig_backup_name'] = \
            WPA_SUPPLICANT_SYSCONFIG_BACKUP_FILE
        # Call the method to configure the connection using the argument
        # dictionary
        self.test_interface.configure_wireless_connection(
            **wireless_connection_settings
        )

if __name__ == '__main__':
    exit(Test().run_test())
