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

import worknode.linux.manager.rhel7.network_interface.vendor_manager_factory

class VendorManagerFactory(worknode.linux.manager.rhel7.network_interface.vendor_manager_factory.VendorManagerFactory):
    """
    VendorManagerFactory provides a method to automatically generate a
    vendor-specific manager object containing any vendor-specific features for
    the network interface card specified.

    """
    def __init__(self):
        super(VendorManagerFactory, self).__init__()
        self.add_module_path(
            path = 'worknode.linux.manager.rhel7.minor_versions.rhel71.network_interface.vendor_manager',
        )
