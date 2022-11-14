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
The worknode.linux.util.rhel7.bluetoothctl module provides a class
(bluetoothctl) that represents the bluetoothctl command line executable.

"""

__author__ = 'Ken Benoit'

import time

import worknode.linux.util.bluetoothctl
from worknode.exception.worknode_executable import *

class bluetoothctl(worknode.linux.util.bluetoothctl.bluetoothctl):
    """
    bluetoothctl represents the bluetoothctl command line executable, which
    provides an interactive command line utility for configuring local and
    remote Bluetooth devices.

    """
    def __init__(self, work_node, command = 'bluetoothctl'):
        super(bluetoothctl, self).__init__(
            work_node = work_node,
            command = command
        )
        self.__configure_bluetoothctl_commands()

    def __configure_bluetoothctl_commands(self):
        # Add all the bluetoothctl commands
        list_commands = self.add_bluetoothctl_command(
            command_identifier = 'list',
            commands = ["list"],
        )
        show_commands = self.add_bluetoothctl_command(
            command_identifier = 'show',
            commands = ["show"],
        )
        select_commands = self.add_bluetoothctl_command(
            command_identifier = 'select',
            commands = ["select"],
        )
        devices_commands = self.add_bluetoothctl_command(
            command_identifier = 'devices',
            commands = ["scan on", time.sleep, "devices", "scan off"],
        )
        power_commands = self.add_bluetoothctl_command(
            command_identifier = 'power',
            commands = ["power"],
        )
        pairable_commands = self.add_bluetoothctl_command(
            command_identifier = 'pairable',
            commands = ["pairable"],
        )
        discoverable_commands = self.add_bluetoothctl_command(
            command_identifier = 'discoverable',
            commands = ["discoverable"],
        )
        agent_commands = self.add_bluetoothctl_command(
            command_identifier = 'agent',
            commands = ["agent"],
        )
        default_agent_commands = self.add_bluetoothctl_command(
            command_identifier = 'default-agent',
            commands = ["default-agent"],
        )
        scan_commands = self.add_bluetoothctl_command(
            command_identifier = 'scan',
            commands = ["scan"],
        )
        info_commands = self.add_bluetoothctl_command(
            command_identifier = 'info',
            commands = ["info"],
        )
        pair_commands = self.add_bluetoothctl_command(
            command_identifier = 'pair',
            commands = ["pair", time.sleep],
        )
        trust_commands = self.add_bluetoothctl_command(
            command_identifier = 'trust',
            commands = ["trust"],
        )
        untrust_commands = self.add_bluetoothctl_command(
            command_identifier = 'untrust',
            commands = ["untrust"],
        )
        block_commands = self.add_bluetoothctl_command(
            command_identifier = 'block',
            commands = ["block"],
        )
        unblock_commands = self.add_bluetoothctl_command(
            command_identifier = 'unblock',
            commands = ["unblock"],
        )
        remove_commands = self.add_bluetoothctl_command(
            command_identifier = 'remove',
            commands = ["remove", time.sleep],
        )
        connect_commands = self.add_bluetoothctl_command(
            command_identifier = 'connect',
            commands = ["connect", time.sleep],
        )
        disconnect_commands = self.add_bluetoothctl_command(
            command_identifier = 'disconnect',
            commands = ["disconnect", time.sleep],
        )
        # Configure all of the parsers for the commands

        # list
        list_parser = list_commands.initialize_command_parser(
            output_type = 'table'
        )
        list_parser.set_column_titles(
            titles = ['mac_address', 'name', 'default']
        )
        list_parser.add_regular_expression(
            regex = '^Controller ' + \
                '(?P<mac_address>([0-9A-F]{2}[:]){5}([0-9A-F]{2})) ' + \
                '(?P<name>\S+)\s*(?P<default>(\[default\])?)'
        )
        # show
        show_parser = show_commands.initialize_command_parser(
            output_type = 'table'
        )
        show_parser.set_column_titles(titles = ['key', 'value'])
        show_parser.add_regular_expression(
            regex = '\s+(?P<key>.+?)\:\s+(?P<value>.+)'
        )
        show_parser.add_regular_expression(
            regex = '(?P<key>^Controller)\s+' + \
                '(?P<value>([0-9A-F]{2}[:]){5}([0-9A-F]{2}))'
        )
        # devices
        devices_parser = devices_commands.initialize_command_parser(
            output_type = 'table'
        )
        devices_parser.set_column_titles(
            titles = ['mac_address', 'name']
        )
        devices_parser.add_regular_expression(
            regex = '^Device ' + \
                '(?P<mac_address>([0-9A-F]{2}[:]){5}([0-9A-F]{2})) ' + \
                '(?P<name>.+)'
        )
        # pair
        pair_parser = pair_commands.initialize_command_parser(
            output_type = 'single'
        )
        pair_parser.set_export_key(key = 'success')
        pair_parser.set_regex(
            regex = '(?P<success>Pairing successful)'
        )
        # remove
        remove_parser = remove_commands.initialize_command_parser(
            output_type = 'single'
        )
        remove_parser.set_export_key(key = 'success')
        remove_parser.set_regex(
            regex = '(?P<success>Device has been removed)'
        )
        # connect
        connect_parser = connect_commands.initialize_command_parser(
            output_type = 'single'
        )
        connect_parser.set_export_key(key = 'success')
        connect_parser.set_regex(
            regex = '(?P<success>Connection successful)'
        )
        # disconnect
        disconnect_parser = disconnect_commands.initialize_command_parser(
            output_type = 'single'
        )
        disconnect_parser.set_export_key(key = 'success')
        disconnect_parser.set_regex(
            regex = '(?P<success>Successful disconnected)'
        )
        # info
        info_parser = info_commands.initialize_command_parser(
            output_type = 'table'
        )
        info_parser.set_column_titles(titles = ['key', 'value'])
        info_parser.add_regular_expression(
            regex = '\s+(?P<key>.+?)\:\s+(?P<value>.+)'
        )

    def list_controllers(self):
        """
        Get a list of local Bluetooth controllers.

        Return value:
        List of dictionaries describing the local Bluetooth controllers.

        """
        controller_list = self.get_bluetoothctl_command(
            command_identifier = 'list'
        ).run_commands()
        return controller_list

    def list_remote_devices(self):
        """
        Get a list of remote Bluetooth devices.

        Return value:
        List of dictionaries describing the remote Bluetooth devices.

        """
        device_list = self.get_bluetoothctl_command(
            command_identifier = 'devices'
        ).run_commands(command_arguments = [None, 15, None, None])
        return device_list

    def get_remote_device(self, mac_address):
        """
        Get a specific remote Bluetooth device.

        Return value:
        Specific dict of remote Bluetooth device.

        """
        device_list = self.get_bluetoothctl_command(
            command_identifier = 'devices'
        ).run_commands(command_arguments = [None, 15, None, None])

        for device in device_list:
            if device['mac_address'] == mac_address:
                return device

        return None

    def set_as_default(self, mac_address):
        """
        Set the provided Bluetooth controller's MAC address as the default
        Bluetooth controller.

        Keyword arguments:
        mac_address - MAC address of the Bluetooth controller to set as the
                      default.

        """
        mac_address = mac_address.upper()
        self.get_bluetoothctl_command(
            command_identifier = 'select'
        ).run_commands(command_arguments = [mac_address])
        if self.get_default_mac_address() != mac_address:
            raise Exception(
                "Unable to set controller {0} as default device".format(
                    mac_address,
                )
            )

    def get_default_mac_address(self):
        """
        Get the default Bluetooth controller's MAC address.

        Return value:
        MAC address of the default Bluetooth controller.

        """
        default_mac = None
        show_output = self.get_bluetoothctl_command(
            command_identifier = 'show'
        ).run_commands()
        for show_dict in show_output:
            if show_dict['key'] == 'Controller':
                default_mac = show_dict['value']
                break
        return default_mac.upper()

    def turn_power_on(self):
        """
        Turn the power on on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'power'
        ).run_commands(command_arguments = ['on'])

    def turn_power_off(self):
        """
        Turn the power off on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'power'
        ).run_commands(command_arguments = ['off'])

    def start_agent(self):
        """
        Start the pairing agent on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'agent'
        ).run_commands(command_arguments = ['on'])

    def stop_agent(self):
        """
        Stop the pairing agent on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'agent'
        ).run_commands(command_arguments = ['off'])

    def enable_default_agent(self):
        """
        Enable the default pairing agent on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'default-agent'
        ).run_commands()

    def enable_pairing(self):
        """
        Enable pairing on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'pairable'
        ).run_commands(command_arguments = ['on'])

    def disable_pairing(self):
        """
        Disable pairing on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'pairable'
        ).run_commands(command_arguments = ['off'])

    def start_scanning(self):
        """
        Start scanning mode on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'scan'
        ).run_commands(command_arguments = ['on'])

    def stop_scanning(self):
        """
        Stop scanning mode on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'scan'
        ).run_commands(command_arguments = ['off'])

    def enable_discovery_mode(self):
        """
        Enable discovery mode on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'discoverable'
        ).run_commands(command_arguments = ['on'])

    def disable_discovery_mode(self):
        """
        Disable discovery mode on the default Bluetooth controller.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'discoverable'
        ).run_commands(command_arguments = ['off'])

    def pair_remote_device(self, mac_address):
        """
        Perform the pairing process with the remote Bluetooth device.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to pair with.

        """
        pair_output = self.get_bluetoothctl_command(
            command_identifier = 'pair'
        ).run_commands(command_arguments = [mac_address.upper(), 10])
        if pair_output['success'] is None:
            raise Exception(
                "Unable to pair with Bluetooth device {mac_address}".format(
                    mac_address = mac_address
                )
            )

    def trust_remote_device(self, mac_address):
        """
        Trust the remote Bluetooth device in order to allow the remote device to
        reconnect itself.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to trust.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'trust'
        ).run_commands(command_arguments = [mac_address.upper()])

    def untrust_remote_device(self, mac_address):
        """
        Untrust the remote Bluetooth device in order to disallow the remote
        device to reconnect itself.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to untrust.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'untrust'
        ).run_commands(command_arguments = [mac_address.upper()])

    def remove_remote_device(self, mac_address):
        """
        Remove the remote Bluetooth device from the list of paired devices.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to remove.

        """
        remove_output = self.get_bluetoothctl_command(
            command_identifier = 'remove'
        ).run_commands(command_arguments = [mac_address.upper(), 5])
        if remove_output['success'] is None:
            raise Exception(
                "Unable to remove Bluetooth device {mac_address}".format(
                    mac_address = mac_address
                )
            )

    def connect_remote_device(self, mac_address):
        """
        Connect to the remote Bluetooth device that was previously paired.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to connect to.

        """
        connect_output = self.get_bluetoothctl_command(
            command_identifier = 'connect'
        ).run_commands(command_arguments = [mac_address.upper(), 5])
        if connect_output['success'] is None:
            raise Exception(
                "Unable to connect to Bluetooth device {mac_address}".format(
                    mac_address = mac_address
                )
            )

    def disconnect_remote_device(self, mac_address):
        """
        Disconnect from the remote Bluetooth device that was previously paired.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to disconnect
                      from.

        """
        disconnect_output = self.get_bluetoothctl_command(
            command_identifier = 'disconnect'
        ).run_commands(command_arguments = [mac_address.upper(), 5])
        if disconnect_output['success'] is None:
            raise Exception(
                "Unable to disconnect from Bluetooth device" + \
                    " {mac_address}".format(
                        mac_address = mac_address
                    )
            )

    def block_remote_device(self, mac_address):
        """
        Add the remote Bluetooth device to the blacklist.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to add to the
                      blacklist.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'block'
        ).run_commands(command_arguments = [mac_address.upper()])

    def unblock_remote_device(self, mac_address):
        """
        Remove the remote Bluetooth devices from the blacklist.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device to remove from
                      the blacklist.

        """
        self.get_bluetoothctl_command(
            command_identifier = 'unblock'
        ).run_commands(command_arguments = [mac_address.upper()])

    def is_paired(self, mac_address):
        """
        Check if the remote Bluetooth device is paired.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device.

        Return values:
        True if device is paired. False if device isn't paired.

        """
        paired = None
        info_output = self.get_bluetoothctl_command(
            command_identifier = 'info'
        ).run_commands(command_arguments = [mac_address.upper()])
        for info_dict in info_output:
            if info_dict['key'] == 'Paired':
                if info_dict['value'] == 'yes':
                    paired = True
                elif info_dict['value'] == 'no':
                    paired = False
                else:
                    raise FailedCommandOutputError(
                        "bluetoothctl info output showed {key} as '{value}'".format(
                            key = info_dict['key'],
                            value = info_dict['value'],
                        )
                    )
                break
        return paired

    def is_trusted(self, mac_address):
        """
        Check if the remote Bluetooth device is trusted.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device.

        Return values:
        True if device is trusted. False if device isn't trusted.

        """
        trusted = None
        info_output = self.get_bluetoothctl_command(
            command_identifier = 'info'
        ).run_commands(command_arguments = [mac_address.upper()])
        for info_dict in info_output:
            if info_dict['key'] == 'Trusted':
                if info_dict['value'] == 'yes':
                    trusted = True
                elif info_dict['value'] == 'no':
                    trusted = False
                else:
                    raise FailedCommandOutputError(
                        "bluetoothctl info output showed {key} as '{value}'".format(
                            key = info_dict['key'],
                            value = info_dict['value'],
                        )
                    )
                break
        return trusted

    def is_blocked(self, mac_address):
        """
        Check if the remote Bluetooth device is blocked.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device.

        Return values:
        True if device is blocked. False if device isn't blocked.

        """
        blocked = None
        info_output = self.get_bluetoothctl_command(
            command_identifier = 'info'
        ).run_commands(command_arguments = [mac_address.upper()])
        for info_dict in info_output:
            if info_dict['key'] == 'Blocked':
                if info_dict['value'] == 'yes':
                    blocked = True
                elif info_dict['value'] == 'no':
                    blocked = False
                else:
                    raise FailedCommandOutputError(
                        "bluetoothctl info output showed {key} as '{value}'".format(
                            key = info_dict['key'],
                            value = info_dict['value'],
                        )
                    )
                break
        return blocked

    def is_connected(self, mac_address):
        """
        Check if the remote Bluetooth device is connected.

        Keyword arguments:
        mac_address - MAC address of the remote Bluetooth device.

        Return values:
        True if device is connected. False if device isn't connected.

        """
        connected = None
        info_output = self.get_bluetoothctl_command(
            command_identifier = 'info'
        ).run_commands(command_arguments = [mac_address.upper()])
        for info_dict in info_output:
            if info_dict['key'] == 'Connected':
                if info_dict['value'] == 'yes':
                    connected = True
                elif info_dict['value'] == 'no':
                    connected = False
                else:
                    raise FailedCommandOutputError(
                        "bluetoothctl info output showed {key} as '{value}'".format(
                            key = info_dict['key'],
                            value = info_dict['value'],
                        )
                    )
                break
        return connected

    def is_powered(self, mac_address):
        """
        Get the power state of the Bluetooth controller requested.

        Return value:
        True if the Bluetooth controller is powered. False if it isn't.

        """
        powered = None
        show_output = self.get_bluetoothctl_command(
            command_identifier = 'show'
        ).run_commands(command_arguments = [mac_address.upper()])
        for show_dict in show_output:
            if show_dict['key'] == 'Powered':
                if show_dict['value'] == 'yes':
                    powered = True
                elif show_dict['value'] == 'no':
                    powered = False
                else:
                    raise FailedCommandOutputError(
                        "bluetoothctl show output showed {key} as '{value}'".format(
                            key = info_dict['key'],
                            value = info_dict['value'],
                        )
                    )
                break
        return powered

    def is_pairable(self, mac_address):
        """
        Get the pairing mode state of the Bluetooth controller requested.

        Return value:
        True if the Bluetooth controller is pairable. False if it isn't.

        """
        pairable = None
        show_output = self.get_bluetoothctl_command(
            command_identifier = 'show'
        ).run_commands(command_arguments = [mac_address.upper()])
        for show_dict in show_output:
            if show_dict['key'] == 'Pairable':
                if show_dict['value'] == 'yes':
                    pairable = True
                elif show_dict['value'] == 'no':
                    pairable = False
                else:
                    raise FailedCommandOutputError(
                        "bluetoothctl show output showed {key} as '{value}'".format(
                            key = info_dict['key'],
                            value = info_dict['value'],
                        )
                    )
                break
        return pairable
