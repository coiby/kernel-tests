#!/usr/bin/python
# Copyright (c) 2017 Red Hat, Inc. All rights reserved. This copyrighted material
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
The functional.ibss.setup.client module provides a class (Test) that sets up and
connects to an IBSS network connection.

"""

__author__ = 'Ken Benoit'

import functional.ibss.functional_ibss_base
import time

class Test(functional.ibss.functional_ibss_base.FunctionalIbssBaseTest):
    """
    Test connects to an already established IBSS connection.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.choose_test_wireless_interface,
            test_step_description = 'Choose which wireless interface to use and describe it',
        )
        self.add_test_step(
            test_step = self.setup_ibss_server,
            test_step_description = 'Have the server set up an IBSS connection',
            rollback_step = self.teardown_ibss_server,
            rollback_step_description = 'Have the server teardown the IBSS connection',
        )
        self.add_test_step(
            test_step = self.configure_test_wireless_interface,
            test_step_description = 'Configure the test wireless interface',
            rollback_step = self.bring_down_wireless_interfaces,
            rollback_step_description = 'Disable the wireless interface',
        )

    def configure_test_wireless_interface(self):
        """
        Configure the wireless interface for the IBSS connection.

        """
        network_name_argument = self.get_command_line_option_value(
            dest = 'network_name',
        )
        self.test_interface.configure_ibss_connection(
            network_name = network_name_argument,
            ssid = self.ssid,
            channel = self.channel,
            ipv4_address = self.client_ip_address,
        )

    def bring_down_wireless_interfaces(self):
        """
        Bring all of the wireless network interfaces down.

        """
        network_name_argument = self.get_command_line_option_value(
            dest = 'network_name',
        )
        network_manager = self.work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()
        for interface in interfaces:
            interface.disable(preferred_command = 'ip')
        self.test_interface.delete_wireless_connection(
            network_name = network_name_argument,
        )
        time.sleep(10)

if __name__ == '__main__':
    exit(Test().run_test())
