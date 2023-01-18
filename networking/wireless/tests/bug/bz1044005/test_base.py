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
The bug.bz1044005.test_base module provides a class (BaseTest) provides the base
test steps for all tests that test BZ 1044005
(https://bugzilla.redhat.com/show_bug.cgi?id=1044005).

"""

__author__ = 'Ken Benoit'

import time

import base.test
from base.exception.test import *
import worknode.worknode_factory
from constants.time import *

class BaseTest(base.test.Test):
    """
    BaseTest provides the base test steps for all tests for BZ 1044005.

    """
    def __init__(self):
        super(BaseTest, self).__init__()
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
        self.test_signal_strength_measurement_timespan = 5 * MINUTE 
        self.test_signal_change_threshold = 15
        self.test_measurement_period = 5

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
            test_step = self.measure_signal_strength,
            test_step_description = 'Measure the signal strength over {0} seconds'.format(self.test_signal_strength_measurement_timespan),
        )
        self.add_test_step(
            test_step = self.bring_down_wireless_interfaces,
            test_step_description = 'Disable the wireless interface',
        )
        self.add_test_step(
            test_step = self.bring_up_wired_interfaces,
            test_step_description = 'Enable the wired network interfaces',
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

    def ping_gateway(self):
        """
        Ping the default gateway address to verify we have a connection.

        """
        if not self.test_interface.is_destination_reachable(destination = '172.17.121.1', timeout = 30, minimum_success_count = 2):
            raise TestFailure("Unable to verify the connection by contacting the gateway")

    def get_work_node(self):
        """
        Generate a work node object to use for the test.

        """
        self.work_node = worknode.worknode_factory.WorkNodeFactory().get_work_node()

    def choose_test_wireless_interface(self):
        """
        Randomly choose a wireless network interface to use for the test.

        """
        network_manager = self.work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()
        if len(interfaces) == 0:
            raise TestFailure("Unable to locate any wireless interfaces")
        random = self.get_random_module()
        self.test_interface = random.choice(interfaces)
        self.get_logger().info("Chosen wireless interface: {0}".format(self.test_interface.get_name()))
        self.get_logger().info("Wireless interface description: {0}".format(self.test_interface.get_descriptive_name()))

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

    def bring_down_wireless_interfaces(self):
        """
        Bring all of the wireless network interfaces down.

        """
        network_manager = self.work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()
        for interface in interfaces:
            interface.disable()
        self.test_interface.delete_wireless_connection(network_name = self.test_network_name)

    def configure_test_wireless_interface(self):
        """
        Configure the wireless test interface for a wireless network.

        """
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
        )

    def measure_signal_strength(self):
        """
        Measure the signal strength to the access point the interface is
        connected to over a span of time and make sure it doesn't fluctuate
        beyond a threshold.
        
        """
        start_time = time.time()
        strength_baseline = self.test_interface.get_signal_strength(ssid = self.test_ssid)
        while time.time() < start_time + self.test_signal_strength_measurement_timespan:
            signal_change = abs(strength_baseline - self.test_interface.get_signal_strength(ssid = self.test_ssid))
            time.sleep(self.test_measurement_period)
            if signal_change > self.test_signal_change_threshold:
                raise TestFailure("Wireless signal level to access point has changed by {change} from the baseline {baseline}".format(change = signal_change, baseline = strength_baseline))

