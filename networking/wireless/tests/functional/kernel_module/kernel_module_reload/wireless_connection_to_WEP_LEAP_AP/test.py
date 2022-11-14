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
The functional.kernel_module.kernel_module_reload.wireless_connection_to_WEP_LEAP_AP
module provides a class (Test) that provides details on how to run the test.

"""

__author__ = 'Ken Benoit'

import functional.kernel_module.kernel_module_reload.kernel_module_reload_base

class Test(functional.kernel_module.kernel_module_reload.kernel_module_reload_base.KernelModuleReloadBaseTest):
    """
    Test performs a functional wireless kernel module reload test.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.set_test_name(name = '/kernel/wireless_tests/functional/kernel_mdoule/kernel_module_reload/wireless_connection_to_WEP_LEAP_AP')
        self.set_test_author(name = 'Ken Benoit', email = 'kbenoit@redhat.com')
        self.set_test_description(description = 'Establish a wireless connection to a WEP LEAP AP, remove the kernel modules for the wireless interface, insert the kernel modules, and re-establish the connection.')

        self.set_ssid(ssid = 'qe-wep-enterprise-cisco')
        self.set_key_management_type(management_type = 'ieee8021x')
        self.set_eap(eap = 'leap')
        self.set_auth_alg(alg = 'leap')
        self.set_identity(identity = 'Bill Smith')
        self.set_password(password = 'testing123')

if __name__ == '__main__':
    exit(Test().run_test())

