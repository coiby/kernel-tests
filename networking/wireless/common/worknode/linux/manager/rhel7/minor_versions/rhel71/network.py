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
The worknode.linux.manager.rhel7.minor_versions.rhel71.network module provides a
class (NetworkManager) that manages all network-related activities.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.manager.rhel7.network
import worknode.linux.manager.rhel7.minor_versions.rhel71.network_interface.vendor_manager_factory

class NetworkManager(worknode.linux.manager.rhel7.network.NetworkManager):
    """
    NetworkManager is an object that manages all network-related activities. It
    acts as a container for network-related commands as well as being a unified
    place to request abstracted network information from.

    """
    def __init__(self, parent):
        super(NetworkManager, self).__init__(parent = parent)
        self._set_wireless_interface_class(class_object = WirelessInterface)
        self._set_wired_interface_class(class_object = WiredInterface)

class WirelessInterface(worknode.linux.manager.rhel7.network.WirelessInterface):
    """
    WirelessInterface represents a wireless network interface on a RHEL7.1 work
    node.

    """
    def __init__(self, parent, name):
        super(WirelessInterface, self).__init__(
            parent = parent,
            name = name,
        )
        self._set_vendor_manager_factory(
            factory = worknode.linux.manager.rhel7.minor_versions.rhel71.network_interface.vendor_manager_factory.VendorManagerFactory(),
        )

class WiredInterface(worknode.linux.manager.rhel7.network.WiredInterface):
    """
    WiredInterface represents a wired network interface on a RHEL7.1 work node.

    """
    def __init__(self, parent, name):
        super(WiredInterface, self).__init__(
            parent = parent,
            name = name,
        )
        self._set_vendor_manager_factory(
            factory = worknode.linux.manager.rhel7.minor_versions.rhel71.network_interface.vendor_manager_factory.VendorManagerFactory(),
        )
