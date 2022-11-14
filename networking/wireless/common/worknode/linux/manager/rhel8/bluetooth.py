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
The worknode.linux.manager.rhel8.bluetooth module provides a class
(BluetoothManager) that manages all Bluetooth-related activities.

"""

__author__ = 'Ken Benoit'

import re
import time

import worknode.linux.manager.bluetooth_base
import worknode.linux.util.hcitool
import worknode.linux.util.rhel8.bluetoothctl
import worknode.linux.util.rhel8.bluez
import worknode.linux.util.rhel8.obex
from worknode.exception.worknode_executable import *
from constants.time import *

class BluetoothManager(worknode.linux.manager.bluetooth_base.BluetoothManager):
    """
    BluetoothManager is an object that manages all Bluetooth-related activities.
    It acts as a container for Bluetooth-related commands as well as being a
    unified place to request abstracted Bluetooth information from and control
    the Bluetooth devices from.

    """
    def __init__(self, parent):
        super(BluetoothManager, self).__init__(parent = parent)
        self.__configure_property_manager()
        self.__commands = {
            'bluetoothctl': worknode.linux.util.rhel8.bluetoothctl.bluetoothctl(
                work_node = self._get_work_node(),
            ),
            'bluez'       : worknode.linux.util.rhel8.bluez.bluez(
                work_node = self._get_work_node(),
            ),
            'obex'       : worknode.linux.util.rhel8.obex.obex(
                work_node = self._get_work_node(),
            ),
        }
        self.access_type = 'bluez'

    def __configure_property_manager(self):
        property_manager = self.get_property_manager()
        # Configure sysfs command manager
        sysfs_command = 'if [ -d /sys/class/bluetooth ]; ' + \
            'then ls -1 /sys/class/bluetooth/|grep -v "\:"; fi'
        # Add the command managers
        sysfs_command_manager = property_manager.add_command_manager(
            manager_name = 'sysfs',
            command = sysfs_command,
        )
        # Set the property mappings
        sysfs_command_manager.set_property_mapping(
            command_property_name = 'bluetooth_device_name',
            internal_property_name = 'bluetooth_device_name',
        )
        # Set up the parsers
        sysfs_parser = sysfs_command_manager.initialize_command_parser(
            parser_type = 'table',
        )
        sysfs_parser.set_column_titles(titles = ['bluetooth_device_name'])
        sysfs_parser.add_regular_expression(
            regex = '(?P<bluetooth_device_name>.+)',
        )
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'bluetooth_device_name',
            command_priority = ['sysfs'],
        )

    def _create_local_bluetooth_device(self, interface_name):
        bt_device = LocalBluetoothDevice(
            parent = self,
            interface_name = interface_name,
        )
        self._add_local_bluetooth_device(bluetooth_device_object = bt_device)

    def set_access_type(self, access_type):
         self.access_type = access_type

    def get_command(self, command):
         return self.__commands[command]

class LocalBluetoothDevice(worknode.linux.manager.bluetooth_base.LocalBluetoothDevice):
    """
    RHEL8 child class for local Bluetooth devices within the work node.

    """
    def __init__(self, parent, interface_name):
        super(LocalBluetoothDevice, self).__init__(
            parent = parent,
            interface_name = interface_name,
        )
        self.parent = parent
        self.access_type = parent.access_type
        self.__configure_executables()
        self.__configure_property_manager()

    def __configure_executables(self):
        # Configure hcitool
        hcitool = self._add_command(
            command_name = 'hcitool',
            command_object = worknode.linux.util.hcitool.hcitool(
                work_node = self._get_work_node(),
            ),
        )
        # Add hcitool dev command
        hcitool_dev_command = hcitool.add_hcitool_command(
            command_string = 'dev',
        )
        hcitool_dev_command_parser = \
            hcitool_dev_command.initialize_command_parser(
                output_type = 'table-row',
            )
        hcitool_dev_command_parser.set_column_titles(
            titles = ['name', 'mac_address'],
        )
        hcitool_dev_command_parser.add_regular_expression(
            regex = '\s+(?P<name>\w+)\s+(?P<mac_address>.+)',
        )
        hcitool_dev_command_parser.set_specified_row(
            column_title = 'name',
            column_value = self.get_interface_name(),
        )
        # Configure bluetoothctl
        bluetoothctl = self._add_command(
            command_name = 'bluetoothctl',
            command_object = \
                worknode.linux.util.rhel8.bluetoothctl.bluetoothctl(
                    work_node = self._get_work_node(),
                ),
        )
        bluez = self._add_command(
            command_name = 'bluez',
            command_object = \
                worknode.linux.util.rhel8.bluez.bluez(
                    work_node = self._get_work_node(),
                    dbus_obj = self.parent.get_command('bluez').dbus_obj,
                ),
        )
        obex = self._add_command(
            command_name = 'obex',
            command_object = \
                worknode.linux.util.rhel8.obex.obex(
                    work_node = self._get_work_node(),
                    dbus_obj = self.parent.get_command('obex').dbus_obj,
                ),
        )

    def __configure_property_manager(self):
        property_manager = self._get_property_manager()
        # Configure hcitool command manager
        hcitool = self._get_command_object(command_name = 'hcitool')
        hcitool_dev_command_object = hcitool.get_hcitool_command(
            command_string = 'dev',
        )
        hcitool_dev_command = hcitool_dev_command_object.get_command()
        hcitool_dev_parser = hcitool_dev_command_object.get_command_parser()
        # Add the command managers
        hcitool_dev_manager = property_manager.add_command_manager(
            manager_name = 'hcitool_dev',
            command = hcitool_dev_command,
        )
        sysfs_mac_address_command_manager = \
            property_manager.add_command_manager(
                manager_name = 'sysfs_mac_address',
                command = 'cat /sys/class/bluetooth/{0}/address'.format(
                    self.get_interface_name()
                )
            )
        # Set the property mappings
        hcitool_dev_manager.set_property_mapping(
            command_property_name = 'mac_address',
            internal_property_name = 'mac_address',
        )
        sysfs_mac_address_command_manager.set_property_mapping(
            command_property_name = 'mac_address',
            internal_property_name = 'mac_address',
        )
        # Set up the parsers
        hcitool_dev_manager.set_command_parser(
            parser = hcitool_dev_parser,
        )
        sysfs_mac_address_parser = \
            sysfs_mac_address_command_manager.initialize_command_parser(
                parser_type = 'single',
            )
        sysfs_mac_address_parser.set_export_key(key = 'mac_address')
        sysfs_mac_address_parser.set_regex(regex = '(.+)')
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'mac_address',
            command_priority = ['hcitool_dev', 'sysfs_mac_address'],
        )

    def is_default(self):
        """
        Check if this local Bluetooth device is the default device.

        Return value:
        True if this is the default device. False if it isn't.

        """
        is_default = False
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        mac_address = bluetoothctl.get_default_mac_address()
        if mac_address == self.get_mac_address():
            is_default = True
        return is_default

    def turn_power_on(self):
        """
        Set the power on for this local Bluetooth device.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        default_device = \
            self._get_manager().get_default_local_bluetooth_device()
        if default_device != self:
            bluetoothctl.set_as_default(mac_address = self.get_mac_address())
        bluetoothctl.turn_power_on()
        if not self.is_powered():
            raise Exception(
                "Unable to power on Bluetooth controller {0}".format(
                    self.get_mac_address(),
                )
            )
        if default_device != self:
            bluetoothctl.set_as_default(
                mac_address = default_device.get_mac_address()
            )

    def turn_power_off(self):
        """
        Set the power off for this local Bluetooth device.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        default_device = \
            self._get_manager().get_default_local_bluetooth_device()
        if default_device != self:
            bluetoothctl.set_as_default(mac_address = self.get_mac_address())
        bluetoothctl.turn_power_off()
        if self.is_powered():
            raise Exception(
                "Unable to power off Bluetooth controller {0}".format(
                    self.get_mac_address(),
                )
            )
        if default_device != self:
            bluetoothctl.set_as_default(
                mac_address = default_device.get_mac_address()
            )

    def is_powered(self):
        """
        Check the power state for this local Bluetooth device.

        Return value:
        True if this device is powered. False if it isn't.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        return bluetoothctl.is_powered(mac_address = self.get_mac_address())

    def enable_pairing(self):
        """
        Turn on pairing mode for this local Bluetooth device.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        default_device = \
            self._get_manager().get_default_local_bluetooth_device()
        if default_device != self:
            bluetoothctl.set_as_default(mac_address = self.get_mac_address())
        bluetoothctl.enable_pairing()
        if not self.is_pairable():
            raise Exception(
                "Unable to enable pairing mode on Bluetooth controller {0}".format(
                    self.get_mac_address(),
                )
            )
        if default_device != self:
            bluetoothctl.set_as_default(
                mac_address = default_device.get_mac_address()
            )

    def disable_pairing(self):
        """
        Turn off pairing mode for this local Bluetooth device.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        default_device = \
            self._get_manager().get_default_local_bluetooth_device()
        if default_device != self:
            bluetoothctl.set_as_default(mac_address = self.get_mac_address())
        bluetoothctl.disable_pairing()
        if self.is_pairable():
            raise Exception(
                "Unable to disable pairing mode on Bluetooth controller {0}".format(
                    self.get_mac_address(),
                )
            )
        if default_device != self:
            bluetoothctl.set_as_default(
                mac_address = default_device.get_mac_address()
            )

    def is_pairable(self):
        """
        Check if pairing mode is enabled for this local Bluetooth device.

        Return value:
        True if this device is pairable. False if it isn't.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        return bluetoothctl.is_pairable(mac_address = self.get_mac_address())

    def _set_as_default(self):
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        bluetoothctl.set_as_default(mac_address = self.get_mac_address())
        bluetoothctl.turn_power_on()
        self.__is_default = True

    def _set_as_not_default(self):
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        bluetoothctl.set_as_default(mac_address = self.get_mac_address())
        bluetoothctl.turn_power_off()
        self.__is_default = False

    def is_default(self):
        return self.__is_default

    def get_remote_bluetooth_devices(self, force_power_switch = True):
        """
        Get a list of all remote Bluetooth device objects discovered during a
        scan.

        Keyword arguments:
        force_power_switch - If True and the default Bluetooth device is not
                             powered before attempting to discover remote
                             Bluetooth devices then it will be automatically
                             turn on the power for the default Bluetooth device.
                             After discovery has completed it will then turn off
                             the power for the default Bluetooth device if the
                             power was off to start with.

        Return value:
        List of RemoteBluetoothDevice objects.

        """
        default_device = self._get_manager().get_default_local_bluetooth_device()
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        initial_power_on = default_device.is_powered()
        if force_power_switch and not initial_power_on:
            default_device.turn_power_on()
        device_list = bluetoothctl.list_remote_devices()
        remote_devices = []
        for device_dict in device_list:
            device_obj = None
            if 'device' in device_dict:
                device_obj = device_dict['device']

            device = RemoteBluetoothDevice(
                parent = self.parent,
                mac_address = device_dict['mac_address'],
                name = device_dict['name'],
                device = device_obj,
            )
            remote_devices.append(device)
        if force_power_switch and not initial_power_on:
            default_device.turn_power_off()
        return remote_devices

    def get_remote_bluetooth_device(self, mac_address):
        """
        Get a specific remote Bluetooth device discovered during a scan.

        Return value:
        List of RemoteBluetoothDevice object.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        bluetoothctl.turn_power_on()
        device_dict = bluetoothctl.get_remote_device(mac_address)

        if not device_dict:
            return None

        device_obj = None
        if 'device' in device_dict:
            device_obj = device_dict['device']

        device = RemoteBluetoothDevice(
            parent = self.parent,
            mac_address = device_dict['mac_address'],
            name = device_dict['name'],
            device = device_obj,
        )

        return device

class RemoteBluetoothDevice(worknode.linux.manager.bluetooth_base.RemoteBluetoothDevice):
    """
    RHEL8 child class for remote Bluetooth devices external from the work node.

    """
    def __init__(self, parent, mac_address, name, device):
        super(RemoteBluetoothDevice, self).__init__(
            parent = parent,
            mac_address = mac_address,
            name = name,
        )
        self.parent = parent
        self.access_type = parent.access_type
        self.device = device
        self.__configure_executables()

    def __configure_executables(self):
        # Configure bluetoothctl
        bluetoothctl = self._add_command(
            command_name = 'bluetoothctl',
            command_object = worknode.linux.util.rhel8.bluetoothctl.bluetoothctl(
                work_node = self._get_work_node(),
            ),
        )
        bluez = self._add_command(
            command_name = 'bluez',
            command_object = \
                worknode.linux.util.rhel8.bluez.bluez(
                    work_node = self._get_work_node(),
                    dbus_obj = self.parent.get_command('bluez').dbus_obj,
                    device = self.device,
                ),
        )
        obex = self._add_command(
            command_name = 'obex',
            command_object = \
                worknode.linux.util.rhel8.obex.obex(
                    work_node = self._get_work_node(),
                    dbus_obj = self.parent.get_command('obex').dbus_obj,
                    device = self.device,
                    mac_address = self.get_mac_address()
                ),
        )

    def pair(self, force_pairable_switch = True):
        """
        Pair this remote Bluetooth device with the work node.

        Keyword arguments:
        force_pairable_switch - If True and the default Bluetooth device is not
                                in pairing mode before attempting to pair then
                                it will be automatically put into pairing mode.
                                After pairing has completed it will then disable
                                pairing mode if pairing mode was disabled to
                                start with.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        default_device = self._get_manager().get_default_local_bluetooth_device()
        initial_pairable_on = default_device.is_pairable()
        if force_pairable_switch and not initial_pairable_on:
            default_device.enable_pairing()
        bluetoothctl.start_agent()
        bluetoothctl.enable_default_agent()
        bluetoothctl.pair_remote_device(mac_address = self.get_mac_address())
        bluetoothctl.stop_agent()
        if force_pairable_switch and not initial_pairable_on:
            default_device.disable_pairing()

    def remove(self):
        """
        Remove this remote Bluetooth device from the work node.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        bluetoothctl.remove_remote_device(mac_address = self.get_mac_address())

    def is_paired(self):
        """
        Check if this remote Bluetooth device is already paired.

        Return value:
        True if paired. False if not paired.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        return bluetoothctl.is_paired(mac_address = self.get_mac_address())

    def connect(self):
        """
        Connect to this remote Bluetooth device with the work node.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        bluetoothctl.connect_remote_device(mac_address = self.get_mac_address())

    def disconnect(self):
        """
        Disconnect from this remote Bluetooth device from the work node.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        bluetoothctl.disconnect_remote_device(
            mac_address = self.get_mac_address()
        )

    def is_connected(self):
        """
        Check if this remote Bluetooth device is already connected.

        Return value:
        True if connected. False if not connected.

        """
        bluetoothctl = self._get_command_object(command_name = self.access_type)
        return bluetoothctl.is_connected(mac_address = self.get_mac_address())
