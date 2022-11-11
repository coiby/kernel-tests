#!/usr/bin/python
# Copyright (c) 2019 Red Hat, Inc. All rights reserved. This copyrighted material
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
The functional.suspend_resume module provides a class (Test) that provides
details on how to run the test.

"""

__author__ = 'Ken Benoit'

import time

import base.test
from base.exception.test import *
import worknode.worknode_factory

class Test(base.test.Test):
    """
    Test performs a functional wireless connection test with a suspend/resume
    cycle to ensure that a wireless connection is maintained throughout.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.work_node = None
        self.wired_interfaces = None
        self.test_interface = None
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
            test_step = self.ping_ip_address,
            test_step_description = 'Ping an IP address to verify connection',
        )
        self.add_test_step(
            test_step = self.suspend_system,
            test_step_description = 'Suspend the system for 30 seconds',
        )
        self.add_test_step(
            test_step = self.delay,
        )
        self.add_test_step(
            test_step = self.ping_ip_address,
            test_step_description = 'Ping an IP address to verify connection',
        )

    def get_work_node(self):
        """
        Generate a work node object to use for the test.

        """
        self.work_node = worknode.worknode_factory.WorkNodeFactory().get_work_node()

    def choose_test_wireless_interface(self):
        """
        Choose a wireless network interface to use for the test.

        """
        network_manager = self.work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()

        if len(interfaces) == 0:
            raise TestFailure("Unable to locate any wireless interfaces")
        random = self.get_random_module()
        self.test_interface = random.choice(interfaces)
        self.get_logger().info("Chosen wireless interface: {0}".format(self.test_interface.get_name()))
        self.get_logger().info("Wireless interface description: {0}".format(self.test_interface.get_descriptive_name()))

    def get_wired_interfaces(self):
        """
        Get the list of wired interfaces.

        """
        network_manager = self.work_node.get_network_component_manager()
        self.wired_interfaces = network_manager.get_wired_interfaces()

    def bring_up_wired_interfaces(self):
        """
        Bring all of the wired network interfaces back up.

        """
        max_up_attempts = 10
        up_attempts = 0
        interface_up = False
        while up_attempts < max_up_attempts:
            for interface in self.wired_interfaces:
                try:
                    interface.enable()
                    interface_up = True
                    break
                except:
                    up_attempts = up_attempts + 1
            if interface_up:
                break

    def bring_down_wired_interfaces(self):
        """
        Bring all of the wired network interfaces down.

        """
        for interface in self.wired_interfaces:
            interface.disable()

    def suspend_system(self):
        """
        Suspend the system for 30 seconds and automatically resume.

        """
        power_manager = self.work_node.get_power_component_manager()
        power_manager.suspend(seconds = 30)

    def ping_ip_address(self):
        """
        Ping an IP address to verify we have a connection.

        """
        if not self.test_interface.is_destination_reachable(
            destination = "www.redhat.com",
            timeout = 30,
            minimum_success_count = 2,
        ):
            raise TestFailure(
                "Unable to verify the connection by contacting www.redhat.com"
            )

    def delay(self):
        """
        Wait for 30 seconds for the wireless connection to re-establish after
        the resume from suspend.

        """
        time.sleep(30)

if __name__ == '__main__':
    exit(Test().run_test())
