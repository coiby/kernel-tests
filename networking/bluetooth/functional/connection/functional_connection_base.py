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
The functional.connection.functional_connection_base module provides a class
(FunctionalConnectionBaseTest) provides the base test steps for all functional
Bluetooth connection-based tests.

"""

__author__ = 'Ken Benoit'

import base.test
from base.exception.test import *
import worknode.worknode_factory

class FunctionalConnectionBaseTest(base.test.Test):
    """
    FunctionalConnectionBaseTest provides the base test steps for all functional
    Bluetooth connection-based tests.

    """
    def __init__(self):
        super(FunctionalConnectionBaseTest, self).__init__()
        self.test_interface = None
        self.work_node = None
        self.add_command_line_option(
            '--testInterface',
            dest = 'test_interface',
            action = 'store',
            default = None,
            help = 'name of the Bluetooth interface to test with',
        )

    def start_bluetooth_service(self):
        """
        Start the bluetooth service if it isn't already started.

        """
        service_manager = self.work_node.get_service_component_manager()
        bluetooth_service = service_manager.get_service(
            service_name = "bluetooth"
        )
        if not bluetooth_service.is_running():
            bluetooth_service.start()

    def choose_test_bluetooth_interface(self):
        """
        Choose a Bluetooth interface to use for the test.

        """
        manager = self.work_node.get_bluetooth_component_manager()
        interfaces = manager.get_local_bluetooth_devices()
        test_interface_argument = self.get_command_line_option_value(
            dest = 'test_interface',
        )
        if len(interfaces) == 0:
            raise TestFailure("Unable to locate any Bluetooth interfaces")
        if test_interface_argument is None:
            random = self.get_random_module()
            self.test_interface = random.choice(interfaces)
        else:
            self.test_interface = manager.get_local_bluetooth_device(
                interface_name = test_interface_argument,
            )
        self.test_interface.set_as_default()
        self.get_logger().info(
            "Chosen Bluetooth interface: {0}".format(
                self.test_interface.get_interface_name()
            )
        )
    def get_work_node(self):
        """
        Generate a work node object to use for the test.

        """
        self.work_node = \
            worknode.worknode_factory.WorkNodeFactory().get_work_node()
