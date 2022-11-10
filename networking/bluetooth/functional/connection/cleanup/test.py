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
The functional.connection.cleanup.test module provides a class (Test) that tears
down a Bluetooth connection.

"""

__author__ = 'Ken Benoit'

import functional.connection.functional_connection_base
from base.exception.test import *

class Test(functional.connection.functional_connection_base.FunctionalConnectionBaseTest):
    """
    Test tears down a Bluetooth connection.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.remote_devices = []

        self.set_test_name(
            name = '/kernel/bluetooth_tests/functional/connection/cleanup'
        )
        self.set_test_author(
            name = 'Ken Benoit',
            email = 'kbenoit@redhat.com'
        )
        self.set_test_description(
            description = 'Teardown a Bluetooth connection.'
        )

        self.add_command_line_option(
            '--MACaddress',
            dest = 'mac_address',
            action = 'store',
            default = None,
            help = 'MAC address of the remote Bluetooth device to teardown the connection',
        )

        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.start_bluetooth_service,
        )
        self.add_test_step(
            test_step = self.find_remote_bluetooth_device,
            test_step_description = 'Find the remote Bluetooth device(s)',
        )
        self.add_test_step(
            test_step = self.disconnect_test_bluetooth_device,
            test_step_description = 'Disconnect from the remote Bluetooth device(s)',
        )
        self.add_test_step(
            test_step = self.remove_test_bluetooth_device,
            test_step_description = 'Unpair the remote Bluetooth device(s)',
        )

    def find_remote_bluetooth_device(self):
        """
        Find a remote Bluetooth device that matches the provided MAC address.

        """
        bluetooth_manager = self.work_node.get_bluetooth_component_manager()
        devices = bluetooth_manager.get_remote_bluetooth_devices()
        mac_address = self.get_command_line_option_value(
            dest = 'mac_address',
        )
        if len(devices) == 0:
            raise TestFailure("Unable to locate any remote Bluetooth devices")
        if mac_address is not None:
            for device in devices:
                if device.get_mac_address().upper() == mac_address.upper():
                    self.remote_devices.append(device)
                    break
            if len(self.remote_devices) == 0:
                raise TestFailure(
                    "Unable to locate remote Bluetooth device with MAC " \
                        + "address {0}".format(mac_address.upper())
                )
        else:
            for device in devices:
                if device.is_connected():
                    self.remote_devices.append(device)

    def remove_test_bluetooth_device(self):
        """
        Unpair from the remote Bluetooth device.

        """
        if len(self.remote_devices) == 0:
            self.get_logger().info("No remote Bluetooth devices discovered")
        for device in self.remote_devices:
            self.get_logger().debug(
                "Preparing to unpair with {name}: {mac_address}".format(
                    name = device.get_name(),
                    mac_address = device.get_mac_address(),
                )
            )
            if device.is_paired():
                device.remove()
                self.get_logger().info(
                    "Unpaired with {name}: {mac_address}".format(
                        name = device.get_name(),
                        mac_address = device.get_mac_address(),
                    )
                )
            else:
                self.get_logger().debug(
                    "Already not paired with {name}: {mac_address}".format(
                        name = device.get_name(),
                        mac_address = device.get_mac_address(),
                    )
                )

    def disconnect_test_bluetooth_device(self):
        """
        Disconnect from the remote Bluetooth device.

        """
        if len(self.remote_devices) == 0:
            self.get_logger().info("No remote Bluetooth devices discovered")
        for device in self.remote_devices:
            self.get_logger().debug(
                "Preparing to disconnect from {name}: {mac_address}".format(
                    name = device.get_name(),
                    mac_address = device.get_mac_address(),
                )
            )
            if device.is_connected():
                device.remove()
                self.get_logger().info(
                    "Disconnected from {name}: {mac_address}".format(
                        name = device.get_name(),
                        mac_address = device.get_mac_address(),
                    )
                )
            else:
                self.get_logger().debug(
                    "Already disconnected from {name}: {mac_address}".format(
                        name = device.get_name(),
                        mac_address = device.get_mac_address(),
                    )
                )

if __name__ == '__main__':
    exit(Test().run_test())
