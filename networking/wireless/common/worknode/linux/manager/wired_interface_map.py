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
The worknode.linux.manager.wired_interface_map module provides a class
(WiredInterfaceMapFactory) that provides a method of getting the descriptive
name of a wired interface according to the vendor.

"""

__author__ = 'Ken Benoit'

import re

import framework

class WiredInterfaceMapFactory(framework.Framework):
    """
    WiredInterfaceMapFactory accepts a vendor ID and a device ID (PCI/USB ID) to
    determine the descriptive name of a wired interface according to the vendor.

    """
    def __init__(self):
        super(WiredInterfaceMapFactory, self).__init__()
        self.__map = {
            0x17aa: {
                0x21f3: 'Intel(R) PRO/1000 Network Connection',
            },
        }

    def get_descriptive_name(self, vendor_id, device_id):
        """
        Given the vendor ID and the device ID get the descriptive name of the
        wired interface.

        Keyword arguments:
        vendor_id - Vendor ID in hex or decimal.
        device_id - Device ID in hex or decimal.

        """
        if type(vendor_id) is str:
            if re.match('^0x', vendor_id):
                vendor_id = int(vendor_id, 16)
            else:
                vendor_id = int(vendor_id)
        else:
            return "Unable to determine descriptive name"
        if type(device_id) is str:
            if re.match('^0x', device_id):
                device_id = int(device_id, 16)
            else:
                device_id = int(device_id)
        else:
            return "Unable to determine descriptive name"

        descriptive_name = '{0:02x}:{1:02x}'.format(vendor_id, device_id)

        if vendor_id in self.__map:
            if device_id in self.__map[vendor_id]:
                descriptive_name = self.__map[vendor_id][device_id]

        return descriptive_name
