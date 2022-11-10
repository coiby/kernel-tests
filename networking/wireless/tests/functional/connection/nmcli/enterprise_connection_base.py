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
The functional.connection.nmcli.enterprise_connection_base module
provides a class (EnterpriseConnectionBaseTest) provides the base test steps for
all wpa_supplicant enterprise connection-based tests.

"""

__author__ = 'Ken Benoit'

import functional.connection.nmcli.connection_base
from base.exception.test import *
import time

class EnterpriseConnectionBaseTest(functional.connection.nmcli.connection_base.ConnectionBaseTest):
    """
    EnterpriseConnectionBaseTest provides the base test steps for all enterprise
    connection-based nmcli tests.

    """
    def __init__(self):
        super(EnterpriseConnectionBaseTest, self).__init__()

        self.get_test_step_list().insert_test_step(
            step_number = 2,
            test_step = self.download_certificates,
            test_step_description = 'Download the certificates needed for authentication',
            rollback_step = self.delete_certificates,
            rollback_step_description = 'Delete the downloaded certificates',
        )
        self.get_test_step_list().insert_test_step(
            step_number = 9,
            test_step = self.delete_certificates,
            test_step_description = 'Delete the downloaded certificates',
        )
