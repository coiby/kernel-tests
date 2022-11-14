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
The functional.connection.wpa_supplicant.wireless_connection_to_WPA2_passphrase_AP
module provides a class (Test) that provides details on how to run the test.

"""

__author__ = 'Ken Benoit'

import functional.connection.wpa_supplicant.connection_base

class Test(functional.connection.wpa_supplicant.connection_base.ConnectionBaseTest):
    """
    Test performs a functional wireless connection test.

    """
    def __init__(self):
        super(Test, self).__init__()
        self.set_test_name(name = '/kernel/wireless_tests/functional/connection/wpa_supplicant/wireless_connection_to_WPA2_passphrase_AP')
        self.set_test_author(name = 'Ken Benoit', email = 'kbenoit@redhat.com')
        self.set_test_description(description = 'Establish a wireless connection to a WPA2 passphrase AP using wpa_supplicant.')

        self.replace_test_step_description(
            pattern = 'Configure the test wireless interface',
            new_description = 'Configure the test wireless interface with a WPA2 passphrase-protected connection using wpa_supplicant',
        )

        self.set_ssid(ssid = 'qe-wpa2-psk')
        self.set_psk(psk = 'over the river and through the woods')
        self.set_key_management_type(management_type = 'wpa-psk')

if __name__ == '__main__':
    exit(Test().run_test())

