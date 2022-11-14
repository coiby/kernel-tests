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
The vendor_manager_factory module provides a way for automatically generating a
vendor specific manager object of the proper type for the network interface it
is being instantiated for.

"""

__author__ = 'Ken Benoit'

import pkgutil
import sys

import framework

class VendorManagerFactory(framework.Framework):
    """
    VendorManagerFactory provides a method to automatically generate a
    vendor-specific manager object containing any vendor-specific features for
    the network interface card specified.

    """
    def __init__(self):
        super(VendorManagerFactory, self).__init__()
        self.__module_paths = []
        self.add_module_path(
            path = 'worknode.linux.manager.network_interface.vendor_manager'
        )

    def add_module_path(self, path):
        """
        Add a path used for importing vendor manager modules.

        Keyword arguments:
        path - String of the path to the vendor manager modules.

        """
        self.__module_paths.append(path)

    def get_vendor_manager(self, network_interface):
        """
        Get a vendor-specific manager for the network interface card specified.

        Keyword arguments:
        network_interface - Object that represents the network interface.

        Return value:
        VendorManager object.

        """
        vendor_id = network_interface.get_vendor_id()
        device_id = network_interface.get_device_id()
        reversed_paths = self.__module_paths
        reversed_paths.reverse()
        for module_path in reversed_paths:
            package = __import__(module_path, fromlist=[module_path])
            prefix = module_path + '.'
            for vendor_manager_module in pkgutil.iter_modules(path = package.__path__, prefix = prefix):
                import_string = vendor_manager_module[1]
                test_module = __import__(import_string, fromlist=[module_path])
                manager = test_module.VendorManager(parent = network_interface)
                if vendor_id == manager.get_vendor_id():
                    if device_id == manager.get_device_id():
                        return manager
        return None
