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
The functional.iw.dev_info_verify module provides a class (Test) that provides
details on how to run the test.

"""

__author__ = 'Ken Benoit'

import base.test
from base.exception.test import *
import worknode.worknode_factory
import re

class Test(base.test.Test):
    def __init__(self):
        super(Test, self).__init__()
        self.set_test_name(name = '/kernel/wireless_tests/functional/iw/dev_info_verify')
        self.set_test_author(name = 'Ken Benoit', email = 'kbenoit@redhat.com')
        self.set_test_description(description = "Verify iw's device info output.")

        self.__work_node = None
        self.__test_interface = None
        self.__interface_info = {}

        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.select_wireless_interface,
            test_step_description = 'Select a wireless interface to test against',
        )
        self.add_test_step(
            test_step = self.get_sys_interface_info,
            test_step_description = 'Get wireless interface info from /sys/class/net',
        )
        self.add_test_step(
            test_step = self.verify_iw_dev_info_output,
            test_step_description = 'Verify the iw dev info output for the wireless interface',
        )

    def get_work_node(self):
        """
        Generate a work node object to use for the test.

        """
        self.__work_node = worknode.worknode_factory.WorkNodeFactory().get_work_node()

    def select_wireless_interface(self):
        """
        Select the wireless interface to test against.

        """
        network_manager = self.__work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()
        if len(interfaces) == 0:
            raise TestFailure("Unable to locate any wireless interfaces")
        random = self.get_random_module()
        self.__test_interface = random.choice(interfaces)
        self.get_logger().info(
            "Chosen wireless interface: {0}".format(
                self.__test_interface.get_name()
            )
        )

    def get_sys_interface_info(self):
        """
        Get wireless interface info from /sys/class/net.

        """
        self.__interface_info['mac_address'] = ''.join(
            self.__work_node.run_command(
                "cat /sys/class/net/{0}/address".format(
                    self.__test_interface.get_name()
                )
            )
        ).strip()
        self.__interface_info['ifindex'] = ''.join(
            self.__work_node.run_command(
                "cat /sys/class/net/{0}/ifindex".format(
                    self.__test_interface.get_name()
                )
            )
        ).strip()

    def verify_iw_dev_info_output(self):
        """
        Verify the iw dev info output for the wireless interface.

        """
        iw_info_output = self.__work_node.run_command(
            "iw dev {0} info".format(self.__test_interface.get_name())
        )

        interface_line = "Interface {0}".format(
            self.__test_interface.get_name()
        )
        ifindex_line = "ifindex {0}".format(self.__interface_info['ifindex'])
        mac_address_line = "addr {0}".format(
            self.__interface_info['mac_address'].lower()
        )

        # Check for some specific lines in the output
        for test_line in [interface_line, ifindex_line, mac_address_line]:
            if not re.search(test_line, ''.join(iw_info_output)):
                raise TestFailure(
                    "'iw dev {0} info' output does not contain '{1}'".format(
                        self.__test_interface.get_name(),
                        test_line,
                    )
                )

        # Do a general output format verification as well
        iw_info_format = \
            "Interface \S+\n" + \
            "\s+ifindex \d\n" + \
            "\s+wdev 0x\d\n" + \
            "\s+addr ([0-9a-f]{2}:){5}[0-9a-f]{2}\n" + \
            "(\s+ssid .+\n)*" + \
            "\s+type \S+\n" + \
            "\s+wiphy \d\n" + \
            "(\s+channel \d+ \(\d+ MHz\), width: \d+ MHz, center1: \d+ MHz\n)*" + \
            "\s+txpower \d+\.\d+ dBm\n"

        if not re.search(iw_info_format, ''.join(iw_info_output)):
            raise TestFailure(
                "'iw dev {0} info' output does not match the general format".format(
                    self.__test_interface.get_name(),
                )
            )

if __name__ == '__main__':
    exit(Test().run_test())
