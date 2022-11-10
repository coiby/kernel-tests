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
The worknode.linux.manager.rhel6.bluetooth module provides a class
(BluetoothManager) that manages all Bluetooth-related activities.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.manager.bluetooth_base
import worknode.linux.util.hcitool
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

    def __configure_property_manager(self):
        property_manager = self.get_property_manager()
        # Configure sysfs command manager
        sysfs_command = 'if [ -d /sys/class/bluetooth ]; then ls -1 /sys/class/bluetooth/; fi'
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

    def _create_local_bluetooth_device(self, name):
        bt_device = LocalBluetoothDevice(
            parent = self,
            name = name,
        )
        self._add_local_bluetooth_device(bluetooth_device_object = bt_device)

class LocalBluetoothDevice(worknode.linux.manager.bluetooth_base.LocalBluetoothDevice):
    """
    RHEL7 child class for local Bluetooth devices within the work node.

    """
    def __init__(self, parent, name):
        super(LocalBluetoothDevice, self).__init__(parent = parent, name = name)
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
        # Add hcitool dev command.
        hcitool_dev_command = hcitool.add_hcitool_command(
            command_string = 'dev',
        )
        hcitool_dev_command_parser = hcitool_dev_command.initialize_command_parser(
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
            column_value = self.get_name(),
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
        sysfs_mac_address_command_manager = property_manager.add_command_manager(
            manager_name = 'sysfs_mac_address',
            command = 'cat /sys/class/bluetooth/{0}/address'.format(
                self.get_name()
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
        sysfs_mac_address_parser = sysfs_mac_address_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        sysfs_mac_address_parser.set_export_key(key = 'mac_address')
        sysfs_mac_address_parser.set_regex(regex = '(.+)')
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'mac_address',
            command_priority = ['hcitool_dev', 'sysfs_mac_address'],
        )
