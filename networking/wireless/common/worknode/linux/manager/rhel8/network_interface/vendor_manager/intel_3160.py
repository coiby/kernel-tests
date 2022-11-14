#!/usr/bin/python
# Copyright (c) 2018 Red Hat, Inc. All rights reserved. This copyrighted material
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
The intel_3160 module provides a base class (VendorManager) for other Intel Dual
Band Wireless-AC 3160 VendorManager objects to inherit from as well as providing
some shared functionality.

"""

__author__ = 'Ken Benoit'

import worknode.linux.manager.network_interface.vendor_manager_base

class VendorManager(worknode.linux.manager.network_interface.vendor_manager_base.VendorManager):
    """
    VendorManager provides a base object for other Intel Dual Band Wireless-AC
    3160 VendorManager objects to inherit from as well as providing some shared
    functionality.

    """
    def __init__(self, parent):
        super(VendorManager, self).__init__(parent = parent)
        self._set_vendor_id(id_string = '0x8086')
        self._set_device_id(id_string = '0x08b3')
        self._set_debugfs_manager(
            manager = worknode.linux.manager.network_interface.vendor_manager_base.DebugFSManager(
                parent = self,
            )
        )
        debugfs_manager = self.get_debugfs_manager()
        debugfs_manager.set_path(
            label = 'firmware_restart',
            path = '/sys/kernel/debug/iwlwifi/0000:04:00.0/iwlmvm/fw_restart',
        )

    def restart_firmware(self):
        debugfs_manager = self.get_debugfs_manager()
        firmware_restart_path = debugfs_manager.get_path('firmware_restart')
        work_node = self._get_work_node()
        work_node.run_command(
            command = 'echo 1 > {path}'.format(path = firmware_restart_path),
        )
