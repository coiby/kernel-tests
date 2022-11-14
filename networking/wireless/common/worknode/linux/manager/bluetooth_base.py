#!/usr/bin/python
# Copyright (c) 2016 Red Hat, Inc. All rights reserved. This copyrighted material
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
The worknode.linux.manager.bluetooth_base module provides a class
(BluetoothManager) that manages all Bluetooth-related activities.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_component_manager
import framework
import worknode.property_manager
from worknode.exception.worknode_executable import *
from constants.time import *

class BluetoothManager(worknode.worknode_component_manager.WorkNodeComponentManager):
    """
    BluetoothManager is an object that manages all Bluetooth-related activities.
    It acts as a container for Bluetooth-related commands as well as being a
    unified place to request abstracted Bluetooth information from and control
    the Bluetooth devices from.

    """
    def __init__(self, parent):
        super(BluetoothManager, self).__init__(parent = parent)
        self.__local_bluetooth_devices = {}
        self.__remote_bluetooth_devices = {}
        self.__property_manager = worknode.property_manager.PropertyManager(
            work_node = self._get_work_node(),
        )
        self.__initialize_property_manager()

    def __initialize_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(
            property_name = 'bluetooth_device_name'
        )

    def _create_local_bluetooth_device(self, name):
        raise NotImplementedError

    def _create_remote_bluetooth_device(self, mac_address, name):
        raise NotImplementedError

    def get_property_manager(self):
        """
        Get the property manager.

        Return value:
        PropertyManager object.

        """
        return self.__property_manager

    def discover_local_bluetooth_devices(self):
        """
        Discover all of the local Bluetooth devices present on the work node.

        """
        self.get_property_manager().refresh_properties()
        bluetooth_device_names = self.get_property_manager().get_property_value(
            property_name = 'bluetooth_device_name',
        )
        self.__clear_local_bluetooth_device_list()
        if bluetooth_device_names is not None:
            for name in bluetooth_device_names:
                self._create_local_bluetooth_device(interface_name = name)

    def _add_local_bluetooth_device(self, bluetooth_device_object):
        """
        Add a local Bluetooth device object to the manager.

        Keyword arguments:
        bluetooth_device_object - LocalBluetoothDevice object.

        """
        if bluetooth_device_object.get_interface_name() is not None:
            self.__local_bluetooth_devices[
                bluetooth_device_object.get_interface_name()
            ] = bluetooth_device_object

    def __clear_local_bluetooth_device_list(self):
        """
        Clear the manager's list of cached LocalBluetoothDevice objects.

        """
        for bluetooth_device in list(self.__local_bluetooth_devices.values()):
            del bluetooth_device
        for key in list(self.__local_bluetooth_devices.keys()):
            del self.__local_bluetooth_devices[key]

    def get_local_bluetooth_device(self, interface_name):
        """
        Get the specified local Bluetooth device object.

        Keyword arguments:
        interface_name - Interface name of the local Bluetooth device to return.

        Return value:
        LocalBluetoothDevice object.

        """
        if interface_name not in self.__local_bluetooth_devices:
            self.discover_local_bluetooth_devices()
        return self.__local_bluetooth_devices[interface_name]

    def get_local_bluetooth_devices(self):
        """
        Get a list of all local Bluetooth device objects.

        Return value:
        List of LocalBluetoothDevice objects.

        """
        if list(self.__local_bluetooth_devices.values()) == []:
            self.discover_local_bluetooth_devices()
        return list(self.__local_bluetooth_devices.values())

    def get_remote_bluetooth_devices(self):
        """
        Get a list of all remote Bluetooth device objects discovered during a
        scan.

        Return value:
        List of RemoteBluetoothDevice objects.

        """
        raise NotImplementedError

    def get_default_local_bluetooth_device(self):
        """
        Get the default local Bluetooth device.

        Return value:
        LocalBluetoothDevice object of the default local Bluetooth device.

        """
        default_device = None
        for local_device in self.get_local_bluetooth_devices():
            if local_device.is_default():
                default_device = local_device
                break
        return default_device

    def _set_default_local_device(self, device):
        for local_device in self.__local_bluetooth_devices.values():
            if local_device is not device:
                local_device._set_as_not_default()
        device._set_as_default()

    def get_default_local_device(self):
        for local_device in self.__local_bluetooth_devices.values():
            if local_device.is_default():
                return local_device

        return None

    def __del__(self):
        self.__clear_local_bluetooth_device_list()
        super(BluetoothManager, self).__del__()

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent})'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
        )

class LocalBluetoothDevice(framework.Framework):
    """
    Base class for local Bluetooth devices within the work node.

    """
    def __init__(self, parent, interface_name):
        super(LocalBluetoothDevice, self).__init__()
        self.__parent = parent
        self.__property_manager = worknode.property_manager.PropertyManager(
            work_node = self._get_work_node(),
        )
        self.__interface_name = interface_name
        self.__is_default = False
        self.__commands = {}
        self.__initialize_property_manager()

    def __initialize_property_manager(self):
        property_manager = self._get_property_manager()
        property_manager.initialize_property(property_name = 'mac_address')

    def _add_command(self, command_name, command_object):
        """
        Adds a command object to the manager.

        Keyword arguments:
        command_name - Name to associate with the command.
        command_object - WorkNodeExecutable object that will execute the
                         command.

        Return value:
        WorkNodeExecutable object.

        """
        self.__commands[command_name] = command_object
        return self.__commands[command_name]

    def _get_command_object(self, command_name):
        """
        Get the requested command object.

        Keyword arguments:
        command_name - Name associated with the command.

        Return value:
        WorkNodeExecutable object.

        """
        if command_name not in self.__commands:
            raise NameError(
                "Command object for {0} doesn't exist".format(command_name)
            )
        return self.__commands[command_name]

    def _get_parent(self):
        return self.__parent

    def _get_manager(self):
        return self._get_parent()

    def _get_work_node(self):
        return self._get_parent()._get_work_node()

    def _get_property_manager(self):
        """
        Get the property manager.

        Return value:
        PropertyManager object.

        """
        return self.__property_manager

    def get_interface_name(self):
        """
        Get the interface name of the local Bluetooth device.

        Return value:
        String representing the name.

        """
        return self.__interface_name

    def get_mac_address(self):
        """
        Get the MAC address of the local Bluetooth device.

        Return value:
        String representing the MAC address.

        """
        return self._get_property_manager().get_property_value(
            property_name = 'mac_address',
        ).upper()

    def set_as_default(self):
        """
        Set this device as the default local Bluetooth device.

        """
        if not self.__is_default:
            self._get_manager()._set_default_local_device(device = self)

    def is_default(self):
        """
        Check if this local Bluetooth device is the default device.

        Return value:
        True if this is the default device. False if it isn't.

        """
        raise NotImplementedError

    def turn_power_on(self):
        """
        Turn the power on for this local Bluetooth device.

        """
        raise NotImplementedError

    def turn_power_off(self):
        """
        Turn the power off for this local Bluetooth device.

        """
        raise NotImplementedError

    def is_powered(self):
        """
        Check the power state for this local Bluetooth device.

        Return value:
        True if this device is powered. False if it isn't.

        """
        raise NotImplementedError

    def enable_pairing(self):
        """
        Turn on pairing mode for this local Bluetooth device.

        """
        raise NotImplementedError

    def disable_pairing(self):
        """
        Turn off pairing mode for this local Bluetooth device.

        """
        raise NotImplementedError

    def is_pairable(self):
        """
        Check if pairing mode is enabled for this local Bluetooth device.

        Return value:
        True if this device is pairable. False if it isn't.

        """
        raise NotImplementedError

    def _set_as_default(self):
        raise NotImplementedError

    def _set_as_not_default(self):
        raise NotImplementedError

    def __del__(self):
        self.__parent = None
        self.__name = None
        del self.__property_manager
        super(LocalBluetoothDevice, self).__del__()

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent}, '.format(
                module = self.__module__,
                class_name = self.__class__.__name__,
                parent = self._get_parent(),
            ) + \
            'interface_name = "{interface_name}")'.format(
                interface_name = self.get_interface_name(),
            )

class RemoteBluetoothDevice(framework.Framework):
    """
    Base class for remote Bluetooth devices external from the work node.

    """
    def __init__(self, parent, mac_address, name):
        super(RemoteBluetoothDevice, self).__init__()
        self.__parent = parent
        self.__mac_address = mac_address
        self.__name = name
        self.__commands = {}

    def _add_command(self, command_name, command_object):
        """
        Adds a command object to the manager.

        Keyword arguments:
        command_name - Name to associate with the command.
        command_object - WorkNodeExecutable object that will execute the
                         command.

        Return value:
        WorkNodeExecutable object.

        """
        self.__commands[command_name] = command_object
        return self.__commands[command_name]

    def _get_command_object(self, command_name):
        """
        Get the requested command object.

        Keyword arguments:
        command_name - Name associated with the command.

        Return value:
        WorkNodeExecutable object.

        """
        if command_name not in self.__commands:
            raise NameError(
                "Command object for {0} doesn't exist".format(command_name)
            )
        return self.__commands[command_name]

    def get_command_object(self, command_name):
        """
        Get the requested command object.

        Keyword arguments:
        command_name - Name associated with the command.

        Return value:
        WorkNodeExecutable object.

        """
        if command_name not in self.__commands:
            raise NameError(
                "Command object for {0} doesn't exist".format(command_name)
            )
        return self.__commands[command_name]

    def _get_parent(self):
        return self.__parent

    def _get_manager(self):
        return self._get_parent()

    def _get_work_node(self):
        return self._get_parent()._get_work_node()

    def get_name(self):
        """
        Get the interface name of the remote Bluetooth device.

        Return value:
        String representing the name.

        """
        return self.__name

    def get_mac_address(self):
        """
        Get the MAC address of the remote Bluetooth device.

        Return value:
        String representing the MAC address.

        """
        return self.__mac_address

    def pair(self):
        """
        Pair this remote Bluetooth device with the work node.

        """
        raise NotImplementedError

    def remove(self):
        """
        Remove this remote Bluetooth device from the work node.

        """
        raise NotImplementedError

    def connect(self):
        """
        Connect to this remote Bluetooth device with the work node.

        """
        raise NotImplementedError

    def disconnect(self):
        """
        Disconnect from this remote Bluetooth device from the work node.

        """
        raise NotImplementedError

    def __del__(self):
        self.__parent = None
        self.__mac_address = None
        self.__name = None
        super(RemoteBluetoothDevice, self).__del__()

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent}, '.format(
                module = self.__module__,
                class_name = self.__class__.__name__,
                parent = self._get_parent(),
            ) + \
            'mac_address = "{mac_address}", name = "{name}")'.format(
                mac_address = self.get_mac_address(),
                name = self.get_name(),
            )
