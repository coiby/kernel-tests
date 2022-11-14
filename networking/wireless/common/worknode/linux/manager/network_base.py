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
The worknode.linux.manager.network module provides a class (NetworkManager) that
manages all network-related activities.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_component_manager
import framework
import worknode.property_manager
from worknode.exception.worknode_executable import *
from constants.time import *
import worknode.linux.manager.wireless_interface_map
import worknode.linux.manager.wired_interface_map

class NetworkManager(worknode.worknode_component_manager.WorkNodeComponentManager):
    """
    NetworkManager is an object that manages all network-related activities. It
    acts as a container for network-related commands as well as being a unified
    place to request abstracted network information from.

    """
    def __init__(self, parent):
        super(NetworkManager, self).__init__(parent = parent)
        self.__network_interfaces = {}
        self.__wireless_interface_names = []
        self.__wired_interface_names = []
        self.__wireless_interface_class = None
        self.__wired_interface_class = None
        self.__property_manager = worknode.property_manager.PropertyManager(work_node = parent)
        self.__initialize_property_manager()

    def refresh_network_interface_list(self):
        self.get_property_manager().refresh_properties()
        interface_names = self.get_property_manager().get_property_value(property_name = 'interface_name')
        self._clear_stored_interfaces()
        for name in interface_names:
            self._create_network_interface(interface_name = name)

    def _set_wireless_interface_class(self, class_object):
        self.__wireless_interface_class = class_object

    def _set_wired_interface_class(self, class_object):
        self.__wired_interface_class = class_object

    def _get_wireless_interface_class(self):
        return self.__wireless_interface_class

    def _get_wired_interface_class(self):
        return self.__wired_interface_class

    def _clear_stored_interfaces(self):
        for interface_name in list(self.__network_interfaces.keys()):
            del self.__network_interfaces[interface_name]
        self.__wireless_interface_names = []
        self.__wired_interface_names = []

    def _add_network_interface(self, interface):
        interface_name = interface.get_name()
        self.__network_interfaces[interface_name] = interface

    def _add_wired_interface_name(self, interface_name):
        self.__wired_interface_names.append(interface_name)

    def _add_wireless_interface_name(self, interface_name):
        self.__wireless_interface_names.append(interface_name)

    def get_property_manager(self):
        """
        Get the property manager.

        Return value:
        PropertyManager object.

        """
        return self.__property_manager

    def __initialize_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'interface_name')

    def get_wireless_interfaces(self, refresh_list = False):
        """
        Get a list of wireless network interface objects.

        Keyword arguments:
        refresh_list - If True force a refresh of the cached network interface
                       objects.

        Return value:
        List of WirelessInterface objects.

        """
        interfaces = []
        if refresh_list:
            self.refresh_network_interface_list()
        elif self.__wireless_interface_names == []:
            self.refresh_network_interface_list()
        for interface_name in self.__wireless_interface_names:
            interfaces.append(self.__network_interfaces[interface_name])
        return interfaces

    def get_wired_interfaces(self, refresh_list = False):
        """
        Get a list of wired network interface objects.

        Keyword arguments:
        refresh_list - If True force a refresh of the cached network interface
                       objects.

        Return value:
        List of WiredInterface objects.
        """
        interfaces = []
        if refresh_list:
            self.refresh_network_interface_list()
        elif self.__wired_interface_names == []:
            self.refresh_network_interface_list()
        for interface_name in self.__wired_interface_names:
            interfaces.append(self.__network_interfaces[interface_name])
        return interfaces

    def get_interface(self, interface_name):
        """
        Get a specific network interface.

        Keyword arguments:
        interface_name - Name of the network interface.

        Return value:
        NetworkInterface-based object.

        """
        if interface_name not in self.__network_interfaces:
            self.refresh_network_interface_list()
        if interface_name not in self.__network_interfaces:
            raise KeyError("Unable to locate network interface {0}".format(interface_name))
        return self.__network_interfaces[interface_name]

    def download_file(self, file_path, output_file = None, timeout = HOUR):
        """
        Abstract: Download the file from the provided path.

        file_path - Path to the remote file.
        output_file - Path to the local file.
        timeout - Maximum time (in seconds) to wait for the file to finish
                  downloading.

        Return value:
        Path to the file locally once it has finished downloading.

        """
        raise NotImplementedError

class NetworkInterface(framework.Framework):
    """
    Base class for different types of network interfaces to inherit from.

    """
    def __init__(self, parent, name):
        super(NetworkInterface, self).__init__()
        self.__parent = parent
        self.__interface_map = None
        self.__descriptive_name = None
        self.__property_manager = worknode.property_manager.PropertyManager(
            work_node = self._get_work_node(),
        )
        self.__name = name
        self.__connected = False
        self.__vendor_manager = None
        self.__vendor_manager_factory = None
        self.__initialize_property_manager()

    def _get_parent(self):
        return self.__parent

    def _get_work_node(self):
        return self._get_manager()._get_work_node()

    def __initialize_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'hardware_address')
        property_manager.initialize_property(property_name = 'ipv4_address')
        property_manager.initialize_property(property_name = 'default_gateway_ipv4_address')
        property_manager.initialize_property(property_name = 'vendor_id')
        property_manager.initialize_property(property_name = 'device_id')

    def _get_interface_map(self):
        return self.__interface_map

    def _set_interface_map(self, interface_map):
        self.__interface_map = interface_map

    def _get_manager(self):
        return self._get_parent()

    def _get_work_node(self):
        return self._get_manager()._get_work_node()

    def _set_connected(self):
        self.__connected = True

    def _set_disconnected(self):
        self.__connected = False

    def _is_connected(self):
        return self.__connected

    def _set_vendor_manager_factory(self, factory):
        self.__vendor_manager_factory = factory

    def _get_vendor_manager_factory(self):
        return self.__vendor_manager_factory

    def _set_vendor_specific_manager(self, manager):
        # TODO: Type-check the manager
        self.__vendor_manager = manager

    def get_property_manager(self):
        """
        Get the property manager.

        Return value:
        PropertyManager object.

        """
        return self.__property_manager

    def get_name(self):
        """
        Get the name of the interface.

        Return value:
        Name of the interface.

        """
        return self.__name

    def get_hardware_address(self):
        """
        Get the hardware (MAC) address of the interface.

        Return value:
        Hardware adddress of the interface.

        """
        return self.get_property_manager().get_property_value(property_name = 'hardware_address')

    def get_interface_ipv4_address(self):
        """
        Get the IPv4 address of the interface.

        Return value:
        A string of the IPv4 address of the interface.

        """
        return self.get_property_manager().get_property_value(property_name = 'ipv4_address')

    def get_default_gateway_ipv4_address(self):
        """
        Get the IPv4 address of the default gateway.

        Return value:
        A string of the default gateway IPv4 address of the interface.

        """
        return self.get_property_manager().get_property_value(property_name = 'default_gateway_ipv4_address')

    def get_vendor_id(self):
        """
        Get the vendor ID of the network interface.

        Return value:
        Vendor ID of the network interface.

        """
        return self.get_property_manager().get_property_value(property_name = 'vendor_id')

    def get_device_id(self):
        """
        Get the device ID of the network interface.

        Return value:
        Device ID of the network interface.

        """
        return self.get_property_manager().get_property_value(property_name = 'device_id')

    def refresh_properties(self):
        """
        Refresh all the cached properties in the property manager.

        """
        self.get_property_manager().refresh_properties()

    def enable(self, preferred_command = None):
        """
        Abstract: Bring the network interface up.

        Keyword arguments:
        preferred_command - Preferred command to use to bring the interface up.

        """
        raise NotImplementedError

    def disable(self, preferred_command = None):
        """
        Abstract: Bring the network interface down.

        Keyword arguments:
        preferred_command - Preferred command to use to bring the interface
                            down.

        """
        raise NotImplementedError

    def request_ipv4_address(self):
        """
        Abstract: Request an IPv4 address for the network interface.

        """
        raise NotImplementedError

    def get_descriptive_name(self):
        """
        Get the descriptive name of the network interface.

        Return value:
        Descriptive name of the network interface, or a string representation of
        the PCI ID.

        """
        if self.__descriptive_name is None:
            vendor_id = self.get_vendor_id()
            device_id = self.get_device_id()
            self.__descriptive_name = self._get_interface_map().get_descriptive_name(vendor_id = vendor_id, device_id = device_id)

        return self.__descriptive_name

    def get_vendor_specific_manager(self):
        """
        Get a manager the provides vendor specific features (such as debugfs
        features).

        """
        if self.__vendor_manager is None:
            if self._get_vendor_manager_factory() is None:
                return None
            else:
                self.__vendor_manager = self._get_vendor_manager_factory().get_vendor_manager(network_interface = self)
        return self.__vendor_manager

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent}, name = "{name}")'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
            name = self.get_name(),
        )

class WirelessInterface(NetworkInterface):
    """
    Class that represents a wireless network interface.

    """
    def __init__(self, parent, name):
        super(WirelessInterface, self).__init__(parent = parent, name = name)
        self._set_interface_map(interface_map = worknode.linux.manager.wireless_interface_map.WirelessInterfaceMapFactory())
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'radio_status')

    def disable_radio(self):
        """
        Abstract: Disable the wireless interface's radio.

        """
        raise NotImplementedError

    def enable_radio(self):
        """
        Abstract: Enable the wireless interface's radio.

        """
        raise NotImplementedError

    def is_radio_enabled(self):
        """
        Abstract: Check if the wireless interface's radio is enabled.

        """
        raise NotImplementedError

class WiredInterface(NetworkInterface):
    """
    Class that represents a wired network interface.

    """
    def __init__(self, parent, name):
        super(WiredInterface, self).__init__(parent = parent, name = name)
        self._set_interface_map(interface_map = worknode.linux.manager.wired_interface_map.WiredInterfaceMapFactory())
