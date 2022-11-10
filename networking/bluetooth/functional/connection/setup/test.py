#!/usr/bin/python
# Copyright (c) 2016 Red Hat, Inc. All rights reserved. This copyrighted material
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
a Bluetooth connection.

"""

__author__ = 'Ken Benoit'

import time
import json

import functional.connection.functional_connection_base
from base.exception.test import *
from worknode.linux.manager.exception.file_system import *

class Test(functional.connection.functional_connection_base.FunctionalConnectionBaseTest):
    """
    Test sets up a Bluetooth connection.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.remote_device = None
        self.test_bluetooth_connection_settings = {
            'mac_address': None,
            'low_energy': False,
        }
        self.settings_to_custom_map = {
            'mac_address': 'custom_mac_address',
            'low_energy': 'custom_low_energy',
        }
        self.preconfigured_setups_file = 'preconfigured_setups.json'

        self.set_test_name(
            name = '/kernel/bluetooth_tests/functional/connection/setup'
        )
        self.set_test_author(
            name = 'Ken Benoit',
            email = 'kbenoit@redhat.com'
        )
        self.set_test_description(
            description = 'Setup a Bluetooth connection.'
        )

        self.add_command_line_option(
            '--connectionPreset',
            dest = 'connection_preset',
            action = 'store',
            default = 'random',
            help = 'name of a connection preset',
        )
        self.add_command_line_option(
            '--customMAC',
            dest = 'custom_mac_address',
            action = 'store',
            default = None,
            help = 'custom MAC address to use as the target Bluetooth device for connection',
        )
        self.add_command_line_option(
            '--customLE',
            dest = 'custom_low_energy',
            action = 'store_true',
            default = None,
            help = 'indicate that the target Bluetooth device is a Bluetooth Low Energy device',
        )

        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.start_bluetooth_service,
        )
        self.add_test_step(
            test_step = self.choose_test_bluetooth_interface,
            test_step_description = 'Choose which Bluetooth interface to use and describe it',
        )
        self.add_test_step(
            test_step = self.determine_connection_information,
            test_step_description = 'Determine the connection information to use',
        )
        self.add_test_step(
            test_step = self.find_remote_bluetooth_device,
            test_step_description = 'Find the remote Bluetooth device',
        )
        self.add_test_step(
            test_step = self.pair_test_bluetooth_device,
            test_step_description = 'Pair with the test Bluetooth device',
            rollback_step = self.remove_test_bluetooth_device,
            rollback_step_description = 'Unpair the test Bluetooth device',
        )
        self.add_test_step(
            test_step = self.connect_test_bluetooth_device,
            test_step_description = 'Connect to the test Bluetooth device',
            rollback_step = self.disconnect_test_bluetooth_device,
            rollback_step_description = 'Disconnect from the test Bluetooth device',
        )

    def determine_connection_information(self):
        """
        Determine the connection information to use when configuring the
        Bluetooth connection.

        """
        connection_preset = self.get_command_line_option_value(
            dest = 'connection_preset',
        )
        bluetooth_connection_settings = {}
        # Check if this is supposed to be a custom connection
        if connection_preset != 'custom':
            preconfigured_setups_file = open(self.preconfigured_setups_file)
            preconfigured_setups = json.load(preconfigured_setups_file)
            preconfigured_setups_file.close()
            # Pick a random connection
            if connection_preset == 'random':
                if len(preconfigured_setups) > 0:
                    settings = self.get_random_module().choice(
                        preconfigured_setups.values()
                    )
                    for key, value in settings.iteritems():
                        bluetooth_connection_settings[key] = value
            # Use the preset connection specified
            else:
                if connection_preset not in preconfigured_setups:
                    raise TestFailure(
                        "Unable to locate a preset for '{0}'".format(
                            connection_preset,
                        )
                    )
                settings = preconfigured_setups[connection_preset]
                for key, value in settings.iteritems():
                    bluetooth_connection_settings[key] = value
        for key in self.test_bluetooth_connection_settings.keys():
            if key in self.settings_to_custom_map:
                custom_arg_name = self.settings_to_custom_map[key]
                custom_arg_value = self.get_command_line_option_value(
                    dest = custom_arg_name,
                )
                if custom_arg_value is not None:
                    bluetooth_connection_settings[key] = custom_arg_value
        for key, value in bluetooth_connection_settings.iteritems():
            self.test_bluetooth_connection_settings[key] = value
        self.get_logger().debug(
            "{0}".format(self.test_bluetooth_connection_settings)
        )

    def find_remote_bluetooth_device(self):
        """
        Find a remote Bluetooth device that matches the provided MAC address or
        a random remote Bluetooth device if no MAC address is provided.

        """
        adapter = self.get_work_manager().get_default_local_device()
        if not adapter:
            raise Exception("No default adapter set!")

        if self.test_bluetooth_connection_settings['mac_address'] is not None:
            mac_address = self.test_bluetooth_connection_settings['mac_address']
            device = adapter.get_remote_bluetooth_device(mac_address)
            self.remote_device = device
        else:
            devices = adapter.get_remote_bluetooth_devices()
            if len(devices) == 0:
                raise TestFailure(
                    "Unable to locate any remote Bluetooth devices in " \
                        + "discovery mode"
                )

            self.remote_device = self.get_random_module().choice(devices)

        if self.remote_device is None:
            raise TestFailure(
                "Unable to locate remote Bluetooth device with MAC " \
                    + "address {0}".format(mac_address.upper())
            )

    def pair_test_bluetooth_device(self):
        """
        Pair with the remote Bluetooth device.

        """
        if not self.test_bluetooth_connection_settings['low_energy']:
            if self.remote_device.is_paired():
                self.get_logger().debug(
                    "Already paired with {name}: {mac_address}".format(
                        name = self.remote_device.get_name(),
                        mac_address = self.remote_device.get_mac_address(),
                    )
                )
            else:
                self.remote_device.pair()
                self.get_logger().debug(
                    "Paired with {name}: {mac_address}".format(
                        name = self.remote_device.get_name(),
                        mac_address = self.remote_device.get_mac_address(),
                    )
                )
        else:
            self.get_logger().debug(
                "Skipping pairing for {name}: {mac_address}".format(
                    name = self.remote_device.get_name(),
                    mac_address = self.remote_device.get_mac_address(),
                )
            )

    def remove_test_bluetooth_device(self):
        """
        Unpair from the remote Bluetooth device.

        """
        if not self.test_bluetooth_connection_settings['low_energy']:
            self.remote_device.remove()
            self.get_logger().debug(
                "Unpaired with {name}: {mac_address}".format(
                    name = self.remote_device.get_name(),
                    mac_address = self.remote_device.get_mac_address(),
                )
            )
        else:
            self.get_logger().debug(
                "Skipping unpairing for {name}: {mac_address}".format(
                    name = self.remote_device.get_name(),
                    mac_address = self.remote_device.get_mac_address(),
                )
            )

    def connect_test_bluetooth_device(self):
        """
        Connect to the remote Bluetooth device.

        """
        if self.remote_device.is_connected():
            self.get_logger().debug(
                "Already connected to {name}: {mac_address}".format(
                    name = self.remote_device.get_name(),
                    mac_address = self.remote_device.get_mac_address(),
                )
            )
        else:
            self.remote_device.connect()
            self.get_logger().debug(
                "Connected to {name}: {mac_address}".format(
                    name = self.remote_device.get_name(),
                    mac_address = self.remote_device.get_mac_address(),
                )
            )

    def disconnect_test_bluetooth_device(self):
        """
        Disconnect from the remote Bluetooth device.

        """
        self.remote_device.disconnect()
        self.get_logger().debug(
            "Disconnected from {name}: {mac_address}".format(
                name = self.remote_device.get_name(),
                mac_address = self.remote_device.get_mac_address(),
            )
        )

if __name__ == '__main__':
    exit(Test().run_test())
