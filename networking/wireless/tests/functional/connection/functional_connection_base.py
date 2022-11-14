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
The functional.connection.functional_connection_base module provides a class
(FunctionalConnectionBaseTest) provides the base test steps for all functional
connection-based tests.

"""

__author__ = 'Ken Benoit'

import base.test
from base.exception.test import *
import worknode.worknode_factory
from functional.connection.functional_connection_constants import *

class FunctionalConnectionBaseTest(base.test.Test):
    """
    FunctionalConnectionBaseTest provides the base test steps for all functional
    connection-based tests.

    """
    def __init__(self):
        super(FunctionalConnectionBaseTest, self).__init__()
        self.ca_cert_url = None
        self.client_cert_url = None
        self.private_key_url = None
        self.ca_cert_required = False
        self.client_cert_required = False
        self.private_key_required = False
        self.local_ca_cert = None
        self.local_client_cert = None
        self.local_private_key = None
        self.test_interface = None
        self.work_node = None
        self.add_command_line_option(
            '--caCertPath',
            dest = 'ca_cert_path',
            action = 'store',
            default = None,
            help = 'path to download the CA (certificate authority) '
                + 'certificate from for the test',
        )
        self.add_command_line_option(
            '--clientCertPath',
            dest = 'client_cert_path',
            action = 'store',
            default = None,
            help = 'path to download the client certificate from for the test',
        )
        self.add_command_line_option(
            '--privateKeyPath',
            dest = 'private_key_path',
            action = 'store',
            default = None,
            help = 'path to download the private key from for the test',
        )
        self.add_command_line_option(
            '--testInterface',
            dest = 'test_interface',
            action = 'store',
            default = None,
            help = 'name of the wireless interface to test with',
        )

    def choose_test_wireless_interface(self):
        """
        Choose a wireless network interface to use for the test.

        """
        network_manager = self.work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()
        test_interface_argument = self.get_command_line_option_value(
            dest = 'test_interface',
        )
        if len(interfaces) == 0:
            raise TestFailure("Unable to locate any wireless interfaces")
        if test_interface_argument is None:
            random = self.get_random_module()
            self.test_interface = random.choice(interfaces)
        else:
            self.test_interface = network_manager.get_interface(
                interface_name = test_interface_argument,
            )
        self.get_logger().info("Chosen wireless interface: {0}".format(self.test_interface.get_name()))
        self.get_logger().info("Wireless interface description: {0}".format(self.test_interface.get_descriptive_name()))

    def get_work_node(self):
        """
        Generate a work node object to use for the test.

        """
        self.work_node = worknode.worknode_factory.WorkNodeFactory().get_work_node()

    def download_certificates(self):
        """
        Download the certificates to be used for authentication.

        """
        network_manager = self.work_node.get_network_component_manager()
        file_system_manager = self.work_node.get_file_system_component_manager()
        cert_directory = file_system_manager.create_directory(
            directory_path = LOCAL_CERT_DIR,
        )
        if self.work_node.get_major_version() >= 8:
            # TODO: This is a temporary workaround for RHEL8+ since OpenSSL
            # changes make current TLS/TTLS testing fail
            self.work_node.run_command(command = 'update-crypto-policies --set LEGACY')
            self.work_node.run_command(command = 'systemctl restart wpa_supplicant')
        if self.is_ca_cert_required():
            self.local_ca_cert = network_manager.download_file(
                file_path = self.get_ca_cert_url(),
                output_file = str(cert_directory) + '/' + CA_CERT_LOCAL_FILE,
            )
        if self.is_client_cert_required():
            self.local_client_cert = network_manager.download_file(
                file_path = self.get_client_cert_url(),
                output_file = str(cert_directory) + '/' + CLIENT_CERT_LOCAL_FILE,
            )
        if self.is_private_key_required():
            self.local_private_key = network_manager.download_file(
                file_path = self.get_private_key_url(),
                output_file = str(cert_directory) + '/' + PRIVATE_KEY_LOCAL_FILE,
            )

    def delete_certificates(self):
        """
        Delete the certificates that were downloaded to the system.

        """
        if self.local_ca_cert is not None:
            self.local_ca_cert.delete()
        if self.local_client_cert is not None:
            self.local_client_cert.delete()
        if self.local_private_key is not None:
            self.local_private_key.delete()

    def require_ca_cert(self, required):
        """
        Set whether or not the CA (certificate authority) certificate is
        required for the test.

        Keyword arguments:
        required - If True then the CA certificate is required. If False then
                   the CA certificate is not required.

        """
        if type(required) is not bool:
            raise TypeError("required needs to be either True or False")
        self.ca_cert_required = required

    def require_client_cert(self, required):
        """
        Set whether or not the client certificate is required for the test.

        Keyword arguments:
        required - If True then the client certificate is required. If False
                   then the client certificate is not required.

        """
        if type(required) is not bool:
            raise TypeError("required needs to be either True or False")
        self.client_cert_required = required

    def require_private_key(self, required):
        """
        Set whether or not the private key is required for the test.

        Keyword arguments:
        required - If True then the private key is required. If False then the
                   private key is not required.

        """
        if type(required) is not bool:
            raise TypeError("required needs to be either True or False")
        self.private_key_required = required

    def is_ca_cert_required(self):
        """
        Check if the CA (certificate authority) certificate is required for the
        test.

        Return value:
        True if the CA certificate is required. False if the CA certificate is
        not required.

        """
        return self.ca_cert_required

    def is_client_cert_required(self):
        """
        Check if the client certificate is required for the test.

        Return value:
        True if the client certificate is required. False if the client
        certificate is not required.

        """
        return self.client_cert_required

    def is_private_key_required(self):
        """
        Check if the private key is required for the test.

        Return value:
        True if the private key is required. False if the private key is not
        required.

        """
        return self.private_key_required

    def get_ca_cert_url(self):
        """
        Get the URL for the CA (certificate authority) certificate.

        Return value:
        URL for the CA certificate.

        """
        if self.ca_cert_url is None:
            ca_cert_path = self.get_command_line_option_value(
                dest = 'ca_cert_path',
            )
            if ca_cert_path is not None:
                self.ca_cert_url = ca_cert_path
            else:
                self.ca_cert_url = CA_CERT_URL
        return self.ca_cert_url

    def get_client_cert_url(self):
        """
        Get the URL for the client certificate.

        Return value:
        URL for the client certificate.

        """
        if self.client_cert_url is None:
            client_cert_path = self.get_command_line_option_value(
                dest = 'client_cert_path',
            )
            if client_cert_path is not None:
                self.client_cert_url = client_cert_path
            else:
                self.client_cert_url = CLIENT_CERT_URL
        return self.client_cert_url

    def get_private_key_url(self):
        """
        Get the URL for the private key.

        Return value:
        URL for the private key.

        """
        if self.private_key_url is None:
            private_key_path = self.get_command_line_option_value(
                dest = 'ca_cert_path',
            )
            if private_key_path is not None:
                self.private_key_url = private_key_path
            else:
                self.private_key_url = PRIVATE_KEY_URL
        return self.private_key_url

    def set_ca_cert_url(self, url):
        """
        Set the URL for the CA (certificate authority) certificate.

        Keyword arguments:
        url - URL for the CA certificate.

        """
        self.ca_cert_url = url

    def set_client_cert_url(self, url):
        """
        Set the URL for the client certificate.

        Keyword arguments:
        url - URL for the client certificate.

        """
        self.client_cert_url = url

    def set_private_key_url(self, url):
        """
        Set the URL for the private key.

        Keyword arguments:
        url - URL for the private key.

        """
        self.private_key_url = url

    def get_local_ca_cert_file(self):
        """
        Get the file object of the local CA (certificate authority) certificate.

        Return value:
        Object representing the CA certificate file.

        """
        return self.local_ca_cert

    def get_local_client_cert_file(self):
        """
        Get the file object of the local client certificate.

        Return value:
        Object representing the client certificate file.

        """
        return self.local_client_cert

    def get_local_private_key_file(self):
        """
        Get the file object of the local private key.

        Return value:
        Object representing the private key file.

        """
        return self.local_private_key

    def set_additional_networking_configuration(self):
        """
        Set additional networking configuration on the system.

        """
        # These commands allows for both a wired interface and wireless
        # interface to be up at the same time on the subnet with both interfaces
        # being accessible at the same time.
        self.work_node.run_command("sysctl net.ipv4.conf.all.rp_filter=2")
        self.work_node.run_command("sysctl net.ipv4.conf.default.rp_filter=2")
