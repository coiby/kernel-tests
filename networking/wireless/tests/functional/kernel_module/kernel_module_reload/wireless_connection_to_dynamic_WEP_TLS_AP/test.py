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
The functional.kernel_module.kernel_module_reload.wireless_connection_to_dynamic_WEP_TLS_AP
module provides a class (Test) that provides details on how to run the test.

"""

__author__ = 'Ken Benoit'

import functional.kernel_module.kernel_module_reload.enterprise_kernel_module_reload_base

class Test(functional.kernel_module.kernel_module_reload.enterprise_kernel_module_reload_base.EnterpriseKernelModuleReloadBaseTest):
    """
    Test performs a functional wireless kernel module reload test.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.set_test_name(name = '/kernel/wireless_tests/functional/kernel_mdoule/kernel_module_reload/wireless_connection_to_dynamic_WEP_TLS_AP')
        self.set_test_author(name = 'Ken Benoit', email = 'kbenoit@redhat.com')
        self.set_test_description(description = 'Establish a wireless connection to a dynamic WEP w/ TLS AP, remove the kernel modules for the wireless interface, insert the kernel modules, and re-establish the connection.')

        # Require the certificates
        self.require_ca_cert(required = True)
        self.require_client_cert(required = True)
        self.require_private_key(required = True)

        self.set_ssid(ssid = 'qe-wep-enterprise')
        self.set_key_management_type(management_type = 'ieee8021x')
        self.set_eap(eap = 'tls')
        self.set_identity(identity = 'Bill Smith')
        self.set_private_key_password(password = '12345testing')

if __name__ == '__main__':
    exit(Test().run_test())
