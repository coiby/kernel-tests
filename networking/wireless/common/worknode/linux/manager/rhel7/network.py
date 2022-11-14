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
The worknode.linux.manager.rhel7.network module provides a class
(NetworkManager) that manages all network-related activities.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.manager.network_base
from constants.time import *
from worknode.exception.worknode_executable import *
import worknode.linux.manager.rhel7.network_interface.vendor_manager_factory
import worknode.linux.util.rhel7.nmcli
import worknode.linux.util.ping
import worknode.linux.util.ifup
import worknode.linux.util.ifdown
import worknode.linux.util.ip
import worknode.linux.util.dhclient
import worknode.linux.util.wget
import worknode.linux.util.dbus_send

class NetworkManager(worknode.linux.manager.network_base.NetworkManager):
    """
    NetworkManager is an object that manages all network-related activities. It
    acts as a container for network-related commands as well as being a unified
    place to request abstracted network information from.

    """
    def __init__(self, parent):
        super(NetworkManager, self).__init__(parent = parent)
        self.__configure_executables()
        self.__configure_property_manager()
        self._set_wireless_interface_class(class_object = WirelessInterface)
        self._set_wired_interface_class(class_object = WiredInterface)

    def __configure_property_manager(self):
        property_manager = self.get_property_manager()
        # Configure nmcli dev status command manager
        nmcli = self.get_command_object(command_name = 'nmcli')
        status_command_string = nmcli.device().get_command(
            command_string = 'status',
        )
        status_command_parser = nmcli.device().get_command_parser(
            command_string = 'status',
        )
        # Configure sysfs command manager
        sysfs_command = 'ls -1 /sys/class/net/'
        # Add the command managers
        nmcli_command_manager = property_manager.add_command_manager(
            manager_name = 'nmcli',
            command = status_command_string,
        )
        sysfs_command_manager = property_manager.add_command_manager(
            manager_name = 'sysfs',
            command = sysfs_command,
        )
        # Set the property mappings
        nmcli_command_manager.set_property_mapping(
            command_property_name = 'DEVICE',
            internal_property_name = 'interface_name',
        )
        sysfs_command_manager.set_property_mapping(
            command_property_name = 'interface_name',
            internal_property_name = 'interface_name',
        )
        # Set up the parsers
        nmcli_command_manager.set_command_parser(parser = status_command_parser)
        sysfs_parser = sysfs_command_manager.initialize_command_parser(
            parser_type = 'table',
        )
        sysfs_parser.set_column_titles(titles = ['interface_name'])
        sysfs_parser.add_regular_expression(regex = '(?P<interface_name>\S+)')
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'interface_name',
            command_priority = ['sysfs', 'nmcli'],
        )

    def __configure_executables(self):
        # Configure nmcli
        nmcli = self.add_command(
            command_name = 'nmcli',
            command_object = worknode.linux.util.rhel7.nmcli.nmcli(
                work_node = self._get_work_node(),
            ),
        )
        # Configure ifup
        ifup = self.add_command(
            command_name = 'ifup',
            command_object = worknode.linux.util.ifup.ifup(
                work_node = self._get_work_node(),
            ),
        )
        ifup._set_success_regex(regex = 'Connection successfully activated')
        # Configure ifdown
        ifdown = self.add_command(
            command_name = 'ifdown',
            command_object = worknode.linux.util.ifdown.ifdown(
                work_node = self._get_work_node(),
            ),
        )
        ifdown._set_success_regex(regex = 'Device state: \d+ \(disconnected\)')
        # Configure ping
        ping = self.add_command(
            command_name = 'ping',
            command_object = worknode.linux.util.ping.ping(
                work_node = self._get_work_node(),
            ),
        )
        # Configure ip
        ip = self.add_command(
            command_name = 'ip',
            command_object = worknode.linux.util.ip.ip(
                work_node = self._get_work_node(),
            )
        )
        # Add ip route object.
        ip_route_object = ip.add_ip_object(object_string = 'route')
        # Add ip route list command.
        ip_route_list = ip_route_object.add_command(command_string = 'list')
        ip_route_list.add_option(option_flag = '--oneline')
        ip_route_list_parser = ip_route_list.initialize_command_parser(
            output_type = 'table',
        )
        ip_route_list_parser.set_column_titles(
            titles = [
                'network_address',
                'device',
                'protocol',
                'scope',
                'ip_address',
                'default_gateway',
            ],
        )
        ip_route_list_parser.add_regular_expression(
            regex = '(?P<network_address>\S+)\s+dev\s+(?P<device>\S*)\s+'
                + 'proto\s+(?P<protocol>\S+)\s+scope\s+(?P<scope>\S+)\s+src\s+'
                + '(?P<ip_address>\S+)',
        )
        ip_route_list_parser.add_regular_expression(
            regex = '(?P<network_address>\S+)\s+proto\s+(?P<protocol>\S+)\s+'
                + 'scope\s+(?P<scope>\S+)\s+src\s+(?P<ip_address>\S+)',
        )
        ip_route_list_parser.add_regular_expression(
            regex = 'default via (?P<default_gateway>\S+)',
        )
        # Add ip addr object.
        ip_addr_object = ip.add_ip_object(object_string = 'addr')
        # Add ip addr show command.
        ip_addr_show = ip_addr_object.add_command(command_string = 'show')
        ip_addr_show.add_option(option_flag = '--oneline')
        # Add ip link object.
        ip_link_object = ip.add_ip_object(object_string = 'link')
        # Add ip link set command.
        ip_link_set_command = ip_link_object.add_command(command_string = 'set')
        # Configure dhclient
        dhclient = self.add_command(
            command_name = 'dhclient',
            command_object = worknode.linux.util.dhclient.dhclient(
                work_node = self._get_work_node(),
            ),
        )
        dhclient.add_option(option_flag = '-d')
        dhclient.add_success_regular_expression(regex = 'bound to')
        dhclient.add_failure_regular_expression(
            regex = 'No DHCPOFFERS received',
        )
        # Configure wget
        wget = self.add_command(
            command_name = 'wget',
            command_object = worknode.linux.util.wget.wget(
                work_node = self._get_work_node(),
            ),
        )
        # The quotes around the file name are actually Unicode, hence the need
        # to escape out everything
        wget.set_local_file_regular_expression(
            regex = '\xe2\x80\x98(?P<file_name>.+?)\xe2\x80\x99 saved',
        )
        wget.add_failure_regular_expression(regex = 'ERROR')
        wget.set_output_file_option(option = '--output-document')
        # Configure dbus-send
        dbus_send = self.add_command(
            command_name = 'dbus-send',
            command_object = worknode.linux.util.dbus_send.dbus_send(
                work_node = self._get_work_node(),
            ),
        )

    def _create_network_interface(self, interface_name):
        type_property_manager = worknode.property_manager.PropertyManager(
            work_node = self._get_work_node(),
        )
        type_property_manager.initialize_property(
            property_name = 'interface_type',
        )
        # Configure nmcli dev list command manager
        nmcli = self.get_command_object(command_name = 'nmcli')
        show_command_string = nmcli.device().get_command(
            command_string = 'show',
            command_arguments = interface_name,
        )
        show_command_parser = nmcli.device().get_command_parser(
            command_string = 'show',
        )
        # Configure sysfs command manager
        sysfs_command = 'if [ -d /sys/class/net/{0}/device/ ]; then if [ -d /sys/class/net/{0}/wireless/ ]; then echo "wifi"; else echo "ethernet"; fi; else echo "unknown"; fi'.format(interface_name)
        # Add the command managers
        nmcli_command_manager = type_property_manager.add_command_manager(
            manager_name = 'nmcli',
            command = show_command_string,
        )
        sysfs_command_manager = type_property_manager.add_command_manager(
            manager_name = 'sysfs',
            command = sysfs_command,
        )
        # Set the property mappings
        nmcli_command_manager.set_property_mapping(
            command_property_name = 'GENERAL.TYPE',
            internal_property_name = 'interface_type',
        )
        sysfs_command_manager.set_property_mapping(
            command_property_name = 'interface_type',
            internal_property_name = 'interface_type',
        )
        # Set up the parsers
        nmcli_command_manager.set_command_parser(parser = show_command_parser)
        sysfs_parser = sysfs_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        sysfs_parser.set_export_key(key = 'interface_type')
        sysfs_parser.set_regex(regex = '(\S+)')
        # Set the command priorities
        type_property_manager.set_command_priority(
            property_name = 'interface_type',
            command_priority = ['sysfs', 'nmcli'],
        )
        # Get the type of the interface
        interface_type = type_property_manager.get_property_value(
            property_name = 'interface_type',
        )
        if interface_type == 'ethernet':
            interface = self._get_wired_interface_class()(
                parent = self,
                name = interface_name,
            )
            self._add_network_interface(interface = interface)
            self._add_wired_interface_name(interface_name = interface_name)
        elif interface_type == 'wifi':
            interface = self._get_wireless_interface_class()(
                parent = self,
                name = interface_name,
            )
            self._add_network_interface(interface = interface)
            self._add_wireless_interface_name(interface_name = interface_name)

    def is_destination_reachable(
        self,
        destination,
        timeout = 30,
        minimum_success_count = 1,
        preferred_command = 'ping'
    ):
        """
        Check that the network destination provided is reachable.

        Keyword arguments:
        destination - The destination host.
        preferred_command - Preferred command to use to check that the
                            destination provided is reachable.

        Return value:
        True if the destination is reachable. False otherwise.

        """
        destination_reachable = False
        # If the command to use is ping
        if preferred_command == 'ping':
            ping = self.get_command_object(command_name = 'ping')
            ping.set_success_regular_expression(
                regex = '{0} received'.format(minimum_success_count),
            )
            try:
                ping.run_command(
                    command_arguments = '-c {count} -w {timeout} {destination}'.format(
                        count = minimum_success_count,
                        timeout = timeout,
                        destination = destination,
                    )
                )
                destination_reachable = True
            except FailedCommandOutputError:
                destination_reachable = False
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError("Unable to find a suitable command to use")
        return destination_reachable

    def download_file(self, file_path, output_file = None, timeout = HOUR):
        """
        Download the file from the provided path.

        file_path - Path to the remote file.
        output_file - Path to the local file.
        timeout - Maximum time (in seconds) to wait for the file to finish
                  downloading.

        Return value:
        Path to the file locally once it has finished downloading.

        """
        local_file_name = None
        if re.search('^http:\/\/', file_path):
            wget = self.get_command_object(command_name = 'wget')
            local_file_name = wget.run_command(
                file_path = file_path,
                output_file_path = output_file,
                timeout = timeout,
            )
        if local_file_name is None:
            raise Exception("Unable to successfully download the file {0}".format(file_path))
        work_node = self._get_work_node()
        file_object = work_node.get_file_system_component_manager().get_file(
            file_path = local_file_name,
        )
        return file_object

    def restart_network_services(
        self,
        service_names = ['wpa_supplicant', 'NetworkManager']
    ):
        """
        Restarts the indicated services that are associated with the networking.

        Keyword arguments:
        service_names - List of service names to restart.

        """
        work_node = self._get_work_node()
        service_manager = work_node.get_service_component_manager()
        for service_name in service_names:
            service_object = service_manager.get_service(
                service_name = service_name,
            )
            service_object.restart()

class WirelessInterface(worknode.linux.manager.network_base.WirelessInterface):
    """
    WirelessInterface represents a wireless network interface on a RHEL7 work
    node.

    """
    def __init__(self, parent, name):
        super(WirelessInterface, self).__init__(parent = parent, name = name)
        self._set_vendor_manager_factory(
            factory = worknode.linux.manager.rhel7.network_interface.vendor_manager_factory.VendorManagerFactory(),
        )
        # Get the nmcli command and parser
        manager = self._get_manager()
        nmcli = manager.get_command_object(command_name = 'nmcli')
        nmcli_command = nmcli.device().get_command(
            command_string = 'show',
            command_arguments = '{0}'.format(self.get_name()),
        )
        nmcli_parser = nmcli.device().get_command_parser(
            command_string = 'show',
        )
        # Get the ip command and parser
        ip = manager.get_command_object(command_name = 'ip')
        ip_route_object = ip.get_ip_object(object_string = 'route')
        route_list_command = ip_route_object.get_command(command_string = 'list')
        ip_route_command = route_list_command.get_command(
            command_arguments = 'dev {0}'.format(self.get_name()),
        )
        ip_addr_object = ip.get_ip_object(object_string = 'addr')
        addr_show_command = ip_addr_object.get_command(command_string = 'show')
        ip_addr_command = addr_show_command.get_command(
            command_arguments = 'dev {0}'.format(self.get_name()),
        )
        # Configure the property manager
        property_manager = self.get_property_manager()
        # Add all the command managers
        nmcli_command_manager = property_manager.add_command_manager(
            manager_name = 'nmcli',
            command = nmcli_command,
        )
        ip_route_ip_address_command_manager = property_manager.add_command_manager(
            manager_name = 'ip_route_ip_address',
            command = ip_route_command,
        )
        ip_route_gateway_address_command_manager = property_manager.add_command_manager(
            manager_name = 'ip_route_gateway_address',
            command = ip_route_command,
        )
        ip_addr_mac_address_command_manager = property_manager.add_command_manager(
            manager_name = 'ip_addr_mac_address',
            command = ip_addr_command,
        )
        sys_vendor_command_manager = property_manager.add_command_manager(
            manager_name = 'sys_vendor',
            command = 'cat /sys/class/net/{0}/device/vendor'.format(
                self.get_name()
            )
        )
        sys_device_command_manager = property_manager.add_command_manager(
            manager_name = 'sys_device',
            command = 'cat /sys/class/net/{0}/device/device'.format(
                self.get_name()
            )
        )
        sys_rfkill_command_manager = property_manager.add_command_manager(
            manager_name = 'sys_rfkill',
            command = 'cat /sys/class/net/{0}/phy80211/rfkill*/state'.format(
                self.get_name()
            )
        )
        # Set all the property mappings
        nmcli_command_manager.set_property_mapping(
            command_property_name = 'IP4-SETTINGS.ADDRESS',
            internal_property_name = 'ipv4_address',
        )
        nmcli_command_manager.set_property_mapping(
            command_property_name = 'IP4-SETTINGS.GATEWAY',
            internal_property_name = 'default_gateway_ipv4_address',
        )
        nmcli_command_manager.set_property_mapping(
            command_property_name = 'GENERAL.HWADDR',
            internal_property_name = 'hardware_address',
        )
        ip_route_ip_address_command_manager.set_property_mapping(
            command_property_name = 'ip_address',
            internal_property_name = 'ipv4_address',
        )
        ip_route_gateway_address_command_manager.set_property_mapping(
            command_property_name = 'default_gateway',
            internal_property_name = 'default_gateway_ipv4_address',
        )
        ip_addr_mac_address_command_manager.set_property_mapping(
            command_property_name = 'hardware_address',
            internal_property_name = 'hardware_address',
        )
        sys_vendor_command_manager.set_property_mapping(
            command_property_name = 'vendor_id',
            internal_property_name = 'vendor_id',
        )
        sys_device_command_manager.set_property_mapping(
            command_property_name = 'device_id',
            internal_property_name = 'device_id',
        )
        sys_rfkill_command_manager.set_property_mapping(
            command_property_name = 'radio_status',
            internal_property_name = 'radio_status',
        )
        # Set up all the parsers
        nmcli_command_manager.set_command_parser(parser = nmcli_parser)
        ip_address_parser = ip_route_ip_address_command_manager.initialize_command_parser(
            parser_type = 'table-row',
        )
        gateway_address_parser = ip_route_gateway_address_command_manager.initialize_command_parser(
            parser_type = 'table-row',
        )
        mac_address_parser = ip_addr_mac_address_command_manager.initialize_command_parser(
            parser_type = 'table-row',
        )
        sys_vendor_parser = sys_vendor_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        sys_device_parser = sys_device_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        sys_rfkill_parser = sys_rfkill_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        ip_address_parser.add_regular_expression(
            regex = '(?P<network_address>\S+)\s+proto\s+(?P<protocol>\S+)\s+'
                + 'scope\s+(?P<scope>\S+)\s+src\s+(?P<ip_address>\S+)',
        )
        ip_address_parser.set_column_titles(
            titles = ['network_address', 'protocol', 'scope', 'ip_address'],
        )
        ip_address_parser.set_specified_row(
            column_title = 'scope',
            column_value = 'link',
        )
        gateway_address_parser.add_regular_expression(
            regex = '(?P<default>default) via (?P<default_gateway>\S+)',
        )
        gateway_address_parser.set_column_titles(
            titles = ['default', 'default_gateway'],
        )
        gateway_address_parser.set_specified_row(
            column_title = 'default',
            column_value = 'default',
        )
        mac_address_parser.add_regular_expression(
            regex = '\d+: (?P<interface_name>\w+): .+?link/ether '
                + '(?P<hardware_address>\S+)',
        )
        mac_address_parser.set_column_titles(
            titles = ['interface_name', 'hardware_address'],
        )
        mac_address_parser.set_specified_row(
            column_title = 'interface_name',
            column_value = self.get_name(),
        )
        sys_vendor_parser.set_export_key(key = 'vendor_id')
        sys_vendor_parser.set_regex(regex = '(0x\w+)')
        sys_device_parser.set_export_key(key = 'device_id')
        sys_device_parser.set_regex(regex = '(0x\w+)')
        sys_rfkill_parser.set_export_key(key = 'radio_status')
        sys_rfkill_parser.set_regex(regex = '(\S+)')
        # Set all the command priorities
        property_manager.set_command_priority(
            property_name = 'ipv4_address',
            command_priority = ['nmcli', 'ip_route_ip_address'],
        )
        property_manager.set_command_priority(
            property_name = 'default_gateway_ipv4_address',
            command_priority = ['nmcli', 'ip_route_gateway_address'],
        )
        property_manager.set_command_priority(
            property_name = 'hardware_address',
            command_priority = ['nmcli', 'ip_addr_mac_address'],
        )
        property_manager.set_command_priority(
            property_name = 'vendor_id',
            command_priority = ['sys_vendor'],
        )
        property_manager.set_command_priority(
            property_name = 'device_id',
            command_priority = ['sys_device'],
        )
        property_manager.set_command_priority(
            property_name = 'radio_status',
            command_priority = ['sys_rfkill'],
        )

    def enable(self, preferred_command = 'nmcli'):
        """
        Bring the network interface up.

        """
        # If the command to use is nmcli
        if preferred_command == 'nmcli':
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            nmcli.device().connect(interface_name = self.get_name())
        # If the command to use is ip
        elif preferred_command == 'ip':
            ip = self._get_manager().get_command_object(command_name = 'ip')
            ip_link = ip.get_ip_object(object_string = 'link')
            ip_link_set = ip_link.get_command(command_string = 'set')
            ip_link_set.run_command(command_arguments = '{0} up'.format(
                self.get_name()),
            )
        # If the command to use is ifup
        elif preferred_command == 'ifup':
            ifup = self._get_manager().get_command_object(command_name = 'ifup')
            ifup.run_command(interface_name = self.get_name(), timeout = 60)
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError("Unable to find a suitable command to use")

    def disable(self, preferred_command = 'nmcli'):
        """
        Bring the network interface down.

        """
        # If the command to use is nmcli
        if preferred_command == 'nmcli':
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            nmcli.device().disconnect(interface_name = self.get_name())
        # If the command to use is ip
        elif preferred_command == 'ip':
            ip = self._get_manager().get_command_object(command_name = 'ip')
            ip_link = ip.get_ip_object(object_string = 'link')
            ip_link_set = ip_link.get_command(command_string = 'set')
            ip_link_set.run_command(command_arguments = '{0} down'.format(
                self.get_name()),
            )
        # If the command to use is ifdown
        elif preferred_command == 'ifdown':
            ifdown = self._get_manager().get_command_object(
                command_name = 'ifdown',
            )
            ifdown.run_command(interface_name = self.get_name())
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError("Unable to find a suitable command to use")

    def request_ipv4_address(self):
        """
        Request an IPv4 address for the network interface.

        """
        dhclient = self._get_manager().get_command_object(
            command_name = 'dhclient',
        )
        output = dhclient.run_command(command_arguments = self.get_name())
        for line in output:
            match = re.search('bound to (?P<ip_address>\S+)', line)
            if match:
                ip_address = match.group('ip_address')
                self.get_property_manager().set_property(
                    property_name = 'ipv4_address',
                    property_value = ip_address,
                )
        self._set_connected()

    def is_destination_reachable(
        self,
        destination,
        timeout = 30,
        minimum_success_count = 1,
        broadcast = False,
        preferred_command = 'ping',
    ):
        """
        Check that the network destination provided is reachable.

        Keyword arguments:
        destination - The destination host.
        timeout - Maximum number of seconds to wait for success.
        minimum_success_count - Number of successes before the destination is
                                deemed reachable.
        broadcast - Enables broadcast mode.
        preferred_command - Preferred command to use to check that the
                            destination provided is reachable.

        Return value:
        True if the destination is reachable. False otherwise.

        """
        destination_reachable = False
        # If the command to use is ping
        if preferred_command == 'ping':
            ping = self._get_manager().get_command_object(command_name = 'ping')
            ping.set_success_regular_expression(
                regex = '{0} received'.format(minimum_success_count),
            )
            command_arguments = ''
            if broadcast:
                command_arguments += '-b '
            command_arguments += '-c {0} '.format(minimum_success_count)
            command_arguments += '-w {0} '.format(timeout)
            command_arguments += '-I {0} '.format(self.get_name())
            command_arguments += destination
            try:
                ping.run_command(command_arguments = command_arguments)
                destination_reachable = True
            except FailedCommandOutputError:
                destination_reachable = False
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError("Unable to find a suitable command to use")
        return destination_reachable

    def configure_wireless_connection(
        self,
        ssid,
        network_name = None,
        key_management = None,
        pairwise = None,
        group = None,
        proto = None,
        psk = None,
        eap = None,
        identity = None,
        ca_cert = None,
        client_cert = None,
        private_key = None,
        private_key_password = None,
        auth_alg = None,
        password = None,
        phase2_autheap = None,
        wep_key_type = None,
        wep_key0 = None,
        wep_key1 = None,
        wep_key2 = None,
        wep_key3 = None,
        hidden = False,
        ipv4_address = None,
        ipv6_address = None,
        enable_debug_logging = True,
        preferred_command = 'nmcli',
        wpa_supplicant_conf_backup_name = None,
        wpa_supplicant_sysconfig_backup_name = None,
        retries = None,
    ):
        """
        Configure and connect to a wireless network.

        Keyword arguments:
        ssid - SSID of the wireless network.
        network_name - Name of the network connection.
        key_management - Type of key management to use (none, 8021x, wpa-psk,
                         wpa-eap).
        pairwise - Pairwise encryption algorithm to use (tkip, ccmp).
        group - Group encryption algorithm to use (wep40, wep104, tkip, ccmp).
        proto - WPA protocol to use (wpa, rsn).
        psk - Pre-shared key for WPA network.
        eap - EAP method to use when authenticating (leap, md5, tls, ttls).
        identity - Identity string for authentication.
        ca_cert - Path to the CA certificate for EAP authentication.
        client_cert - Path to the client certificate for EAP authentication.
        private_key - Path to the private key for TLS EAP authentication.
        private_key_password - Password to decrypt the private key provided in
                               private_key.
        auth_alg - Authentication algorithm required by a WEP AP.
        password - Password string for authentication.
        phase2_autheap - Specifies the allowed 'phase 2' inner EAP-based
                         authentication methods when an EAP method that uses an
                         inner TLS tunnel is specified in the 'eap' property.
        wep_key_type - 1 if WEP key is hexadecimal or ASCII, 2 if WEP key MD5
                       hashed passphrase.
        wep_key0 - Index 0 WEP key.
        wep_key1 - Index 1 WEP key.
        wep_key2 - Index 2 WEP key.
        wep_key3 - Index 3 WEP key.
        hidden - If True then the wireless network being connected to does not
                 broadcast its SSID.
        ipv4_address - IPv4 address to assign to the connection (with subnet
                       mask).
        ipv6_address - IPv6 address to assign to the connection (with subnet
                       mask).
        enable_debug_logging - Enables debug logging.
        preferred_command - Command to use to configure the wireless network.
        wpa_supplicant_conf_backup_name - Path to use when backing up the
                                          wpa_supplicant.conf file.
        wpa_supplicant_sysconfig_backup_name - Path to use when backing up the
                                               wpa_supplicant sysconfig file.
        retries - Number of times to re-attempt to bring up the wireless
                  connection if the first try fails.

        """
        # If the preferred command is nmcli
        if preferred_command == 'nmcli':
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            if enable_debug_logging:
                nmcli.general().set_logging(
                    level = 'TRACE',
                )
                dbus_send = self._get_manager().get_command_object(
                    command_name = 'dbus-send',
                )
                dbus_send.send_message(
                    object_path = '/fi/w1/wpa_supplicant1',
                    interface = 'org.freedesktop.DBus.Properties.Set',
                    arguments = [
                        'string:fi.w1.wpa_supplicant1',
                        'string:DebugLevel',
                        'variant:string:"debug"',
                    ],
                    bus = 'system',
                    message_type = 'method_call',
                    destination = 'fi.w1.wpa_supplicant1',
                )
            nmcli.connection().create_wireless_connection(
                interface_name = self.get_name(),
                ssid = ssid,
                name = network_name,
                key_management = key_management,
                pairwise = pairwise,
                group = group,
                proto = proto,
                psk = psk,
                eap = eap,
                identity = identity,
                ca_cert = ca_cert,
                client_cert = client_cert,
                private_key = private_key,
                private_key_password = private_key_password,
                auth_alg = auth_alg,
                password = password,
                phase2_autheap = phase2_autheap,
                wep_key_type = wep_key_type,
                wep_key0 = wep_key0,
                wep_key1 = wep_key1,
                wep_key2 = wep_key2,
                wep_key3 = wep_key3,
                hidden = hidden,
                ipv4_address = ipv4_address,
                ipv6_address = ipv6_address,
                retries = retries,
            )
            self._set_connected()
        # If the preferred command is wpa_supplicant
        elif preferred_command == 'wpa_supplicant':
            config_file_manager = self._get_work_node().get_config_file_component_manager()
            # Set up the wpa_supplicant.conf file.
            wpa_supplicant_conf = config_file_manager.get_config_file_object(
                config_file_name = 'wpa_supplicant.conf',
            )
            wpa_supplicant_conf.backup_file(
                backup_name = wpa_supplicant_conf_backup_name,
            )
            wpa_supplicant_conf.set_eapol_version(property_value = '1')
            wpa_supplicant_conf.set_ap_scan(property_value = '1')
            wpa_supplicant_conf.set_fast_reauth(property_value = '1')
            index = wpa_supplicant_conf.create_network_block()
            wpa_supplicant_conf.set_network_ssid(
                property_value = '"{0}"'.format(ssid),
                block = index,
            )
            if key_management is not None:
                wpa_supplicant_conf.set_network_key_mgmt(
                    property_value = key_management.upper(),
                    block = index,
                )
            else:
                wpa_supplicant_conf.set_network_key_mgmt(
                    property_value = 'NONE',
                    block = index,
                )
            if pairwise is not None:
                wpa_supplicant_conf.set_network_pairwise(
                    property_value = pairwise.upper(),
                    block = index,
                )
            if group is not None:
                wpa_supplicant_conf.set_network_group(
                    property_value = group.upper(),
                    block = index,
                )
            if proto is not None:
                wpa_supplicant_conf.set_network_proto(
                    property_value = proto.upper(),
                    block = index,
                )
            if psk is not None:
                wpa_supplicant_conf.set_network_psk(
                    property_value = '"{0}"'.format(psk),
                    block = index,
                )
            if eap is not None:
                wpa_supplicant_conf.set_network_eap(
                    property_value = eap.upper(),
                    block = index,
                )
            if identity is not None:
                wpa_supplicant_conf.set_network_identity(
                    property_value = '"{0}"'.format(identity),
                    block = index,
                )
            if ca_cert is not None:
                wpa_supplicant_conf.set_network_ca_cert(
                    property_value = '"{0}"'.format(ca_cert),
                    block = index,
                )
            if client_cert is not None:
                wpa_supplicant_conf.set_network_client_cert(
                    property_value = '"{0}"'.format(client_cert),
                    block = index,
                )
            if private_key is not None:
                wpa_supplicant_conf.set_network_private_key(
                    property_value = '"{0}"'.format(private_key),
                    block = index,
                )
            if private_key_password is not None:
                wpa_supplicant_conf.set_network_private_key_passwd(
                    property_value = '"{0}"'.format(private_key_password),
                    block = index,
                )
            if auth_alg is not None:
                wpa_supplicant_conf.set_network_auth_alg(
                    property_value = auth_alg.upper(),
                    block = index,
                )
            if password is not None:
                wpa_supplicant_conf.set_network_password(
                    property_value = '"{0}"'.format(password),
                    block = index,
                )
            if phase2_autheap is not None:
                wpa_supplicant_conf.set_network_phase2(
                    property_value = '"autheap={0}"'.format(
                        phase2_autheap.upper(),
                    ),
                    block = index,
                )
            if wep_key0 is not None:
                wpa_supplicant_conf.set_network_wep_key0(
                    property_value = '{0}'.format(wep_key0),
                    block = index,
                )
            if wep_key1 is not None:
                wpa_supplicant_conf.set_network_wep_key1(
                    property_value = '{0}'.format(wep_key1),
                    block = index,
                )
            if wep_key2 is not None:
                wpa_supplicant_conf.set_network_wep_key2(
                    property_value = '{0}'.format(wep_key2),
                    block = index,
                )
            if wep_key3 is not None:
                wpa_supplicant_conf.set_network_wep_key3(
                    property_value = '{0}'.format(wep_key3),
                    block = index,
                )
            if hidden:
                wpa_supplicant_conf.set_network_scan_ssid(property_value = '1')
            wpa_supplicant_conf.write()
            # Set up the sysconfig/wpa_supplicant file.
            wpa_supplicant_sysconfig = config_file_manager.get_config_file_object(
                config_file_name = 'wpa_supplicant',
            )
            wpa_supplicant_sysconfig.backup_file(
                backup_name = wpa_supplicant_sysconfig_backup_name,
            )
            wpa_supplicant_sysconfig.add_interface(
                interface_name = self.get_name(),
            )
            wpa_supplicant_sysconfig.set_log_file_path(
                log_file_path = '/var/log/wpa_supplicant.log',
            )
            wpa_supplicant_sysconfig.set_pid_file_path(
                pid_file_path = '/var/run/wpa_supplicant.pid',
            )
            wpa_supplicant_sysconfig.enable_timestamps()
            if enable_debug_logging:
                wpa_supplicant_sysconfig.set_debug_level(debug_level = 3)
                dbus_send = self._get_manager().get_command_object(
                    command_name = 'dbus-send',
                )
                dbus_send.send_message(
                    object_path = '/fi/w1/wpa_supplicant1',
                    interface = 'org.freedesktop.DBus.Properties.Set',
                    arguments = [
                        'string:fi.w1.wpa_supplicant1',
                        'string:DebugLevel',
                        'variant:string:"debug"',
                    ],
                    bus = 'system',
                    message_type = 'method_call',
                    destination = 'fi.w1.wpa_supplicant1',
                )
            wpa_supplicant_sysconfig.write()
            # Restart wpa_supplicant
            service_manager = self._get_work_node().get_service_component_manager()
            wpa_supplicant_service = service_manager.get_service(
                service_name = 'wpa_supplicant',
            )
            network_manager_service = service_manager.get_service(
                service_name = 'NetworkManager',
            )
            # TODO: Abstract command to truncate wpa_supplicant.log
            self._get_work_node().run_command(
                command = '>| /var/log/wpa_supplicant.log',
            )
            network_manager_service.stop()
            if wpa_supplicant_service.is_running():
                wpa_supplicant_service.restart()
            else:
                wpa_supplicant_service.start()
            self.request_ipv4_address()
            self._set_connected()
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError("Unable to find a suitable command to use")

    def configure_ibss_connection(
        self,
        ssid,
        network_name = None,
        channel = None,
        ipv4_address = None,
        ipv6_address = None,
        enable_debug_logging = True,
        preferred_command = 'nmcli',
    ):
        """
        Configure and connect to an IBSS (wireless ad hoc) network.

        Keyword arguments:
        ssid - SSID of the wireless network.
        network_name - Name of the network connection.
        channel - 802.11 channel to use for the IBSS connection.
        ipv4_address - IPv4 address to assign to the connection (with subnet
                       mask).
        ipv6_address - IPv6 address to assign to the connection (with subnet
                       mask).
        enable_debug_logging - Enables debug logging.
        preferred_command - Command to use to configure the IBSS connection.

        """
        # If the preferred command is nmcli
        if preferred_command == 'nmcli':
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            if enable_debug_logging:
                nmcli.general().set_logging(
                    level = 'TRACE',
                )
                dbus_send = self._get_manager().get_command_object(
                    command_name = 'dbus-send',
                )
                dbus_send.send_message(
                    object_path = '/fi/w1/wpa_supplicant1',
                    interface = 'org.freedesktop.DBus.Properties.Set',
                    arguments = [
                        'string:fi.w1.wpa_supplicant1',
                        'string:DebugLevel',
                        'variant:string:"debug"',
                    ],
                    bus = 'system',
                    message_type = 'method_call',
                    destination = 'fi.w1.wpa_supplicant1',
                )
            nmcli.connection().create_ibss_connection(
                interface_name = self.get_name(),
                ssid = ssid,
                name = network_name,
                channel = channel,
                ipv4_address = ipv4_address,
                ipv6_address = ipv6_address,
            )
            self._set_connected()
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError("Unable to find a suitable command to use")

    def delete_wireless_connection(
        self,
        network_name,
        preferred_command = 'nmcli',
        wpa_supplicant_conf_backup_name = None,
        wpa_supplicant_sysconfig_backup_name = None,
    ):
        """
        Delete a previously configured wireless network.

        Keyword arguments:
        network_name - The name the network was created under.
        preferred_command - The method used to delete the wireless connection.
        wpa_supplicant_conf_backup_name - Path to use when backing up the
                                          wpa_supplicant.conf file.
        wpa_supplicant_sysconfig_backup_name - Path to use when backing up the
                                               wpa_supplicant sysconfig file.

        """
        # If the preferred command is nmcli
        if preferred_command == 'nmcli':
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            nmcli.connection().bring_down_connection(name = network_name)
            nmcli.connection().delete_connection(name = network_name)
            self._set_disconnected()
        # If the preferred command is wpa_supplicant
        elif preferred_command == 'wpa_supplicant':
            service_manager = self._get_work_node().get_service_component_manager()
            network_manager_service = service_manager.get_service(
                service_name = 'NetworkManager',
            )
            config_file_manager = self._get_work_node().get_config_file_component_manager()
            # Restore the wpa_supplicant.conf file.
            wpa_supplicant_conf = config_file_manager.get_config_file_object(
                config_file_name = 'wpa_supplicant.conf',
            )
            wpa_supplicant_conf.restore_file(
                backup_name = wpa_supplicant_conf_backup_name,
            )
            # Restore the sysconfig/wpa_supplicant file.
            wpa_supplicant_sysconfig = config_file_manager.get_config_file_object(
                config_file_name = 'wpa_supplicant',
            )
            wpa_supplicant_sysconfig.restore_file(
                wpa_supplicant_sysconfig_backup_name,
            )
            # Start up the NetworkManager service.
            network_manager_service.start()
            self._set_disconnected()
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )

    def disable_radio(self, preferred_command = 'nmcli'):
        """
        Disable the wireless interface's radio.

        Keyword arguments:
        preferred_command - Preferred command to use when disabling the wifi
                            radio.

        """
        if preferred_command == 'nmcli':
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            nmcli.radio().disable_wifi_radio()
            if nmcli.radio().is_wifi_radio_enabled():
                raise FailedCommandOutputError(
                    "Failed to disable the wireless radio"
                )
            self.get_property_manager().refresh_properties()
            if self.is_radio_enabled():
                raise FailedCommandOutputError(
                    "Failed to disable the wireless radio"
                )
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )

    def enable_radio(self, preferred_command = 'nmcli'):
        """
        Enable the wireless interface's radio.

        Keyword arguments:
        preferred_command - Preferred command to use when enabling the wifi
                            radio.

        """
        if preferred_command == 'nmcli':
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            nmcli.radio().enable_wifi_radio()
            if not nmcli.radio().is_wifi_radio_enabled():
                raise FailedCommandOutputError(
                    "Failed to enable the wireless radio"
                )
            self.get_property_manager().refresh_properties()
            if not self.is_radio_enabled():
                raise FailedCommandOutputError(
                    "Failed to enable the wireless radio"
                )
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )

    def is_radio_enabled(self):
        """
        Check if the wireless interface's radio is enabled.

        Return value:
        True if the radio is enabled. False if the radio is disabled.

        """
        radio_status = self.get_property_manager().get_property_value(
            property_name = 'radio_status',
        )
        if radio_status == '1':
            return True
        elif radio_status == '0':
            return False
        else:
            raise Exception("Wireless radio status unknown")

    def get_signal_strength(self, ssid, preferred_command = 'nmcli'):
        """
        Get the signal level to the provided SSID.

        Keyword arguments:
        ssid - SSID of the wireless network.
        preferred_command - Command to use to get the signal level.

        Return value:
        Signal level.

        """
        signal_level = None
        if preferred_command == 'nmcli':
            ap_entry = None
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            parsed_output = nmcli.device().show_details(
                interface_name = self.get_name(),
            )
            for (key, value) in parsed_output.items():
                if ap_entry is not None:
                    break
                elif re.search('AP.*?SSID', key):
                    if value == ssid:
                        match = re.search('(?P<ap_entry>\S+?)\.SSID', key)
                        ap_entry = match.group('ap_entry')
            signal_level = int(parsed_output[ap_entry + '.SIGNAL'])
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )
        if signal_level is None:
            raise FailedCommandOutputError(
                "Unable to find the signal strength to SSID {0}".format(ssid)
            )
        return signal_level

class WiredInterface(worknode.linux.manager.network_base.WiredInterface):
    """
    WiredInterface represents a wired network interface on a RHEL7 work node.

    """
    def __init__(self, parent, name):
        super(WiredInterface, self).__init__(parent = parent, name = name)
        self._set_vendor_manager_factory(
            factory = worknode.linux.manager.rhel7.network_interface.vendor_manager_factory.VendorManagerFactory(),
        )
        # Get the nmcli command and parser
        manager = self._get_manager()
        nmcli = manager.get_command_object(command_name = 'nmcli')
        nmcli_command = nmcli.device().get_command(
            command_string = 'show',
            command_arguments = '{0}'.format(self.get_name()),
        )
        nmcli_parser = nmcli.device().get_command_parser(
            command_string = 'show',
        )
        # Get the ip command and parser
        ip = manager.get_command_object(command_name = 'ip')
        ip_route_object = ip.get_ip_object(object_string = 'route')
        route_list_command = ip_route_object.get_command(
            command_string = 'list',
        )
        ip_route_command = route_list_command.get_command(
            command_arguments = 'dev {0}'.format(self.get_name()),
        )
        ip_addr_object = ip.get_ip_object(object_string = 'addr')
        addr_show_command = ip_addr_object.get_command(command_string = 'show')
        ip_addr_command = addr_show_command.get_command(
            command_arguments = 'dev {0}'.format(self.get_name()),
        )
        # Configure the property manager
        property_manager = self.get_property_manager()
        # Add all the command managers
        nmcli_command_manager = property_manager.add_command_manager(
            manager_name = 'nmcli',
            command = nmcli_command,
        )
        ip_route_ip_address_command_manager = property_manager.add_command_manager(
            manager_name = 'ip_route_ip_address',
            command = ip_route_command,
        )
        ip_route_gateway_address_command_manager = property_manager.add_command_manager(
            manager_name = 'ip_route_gateway_address',
            command = ip_route_command,
        )
        ip_addr_mac_address_command_manager = property_manager.add_command_manager(
            manager_name = 'ip_addr_mac_address',
            command = ip_addr_command,
        )
        sys_vendor_command_manager = property_manager.add_command_manager(
            manager_name = 'sys_vendor',
            command = 'cat /sys/class/net/{0}/device/vendor'.format(
                self.get_name(),
            ),
        )
        sys_device_command_manager = property_manager.add_command_manager(
            manager_name = 'sys_device',
            command = 'cat /sys/class/net/{0}/device/device'.format(
                self.get_name(),
            ),
        )
        # Set all the property mappings
        nmcli_command_manager.set_property_mapping(
            command_property_name = 'IP4-SETTINGS.ADDRESS',
            internal_property_name = 'ipv4_address',
        )
        nmcli_command_manager.set_property_mapping(
            command_property_name = 'IP4-SETTINGS.GATEWAY',
            internal_property_name = 'default_gateway_ipv4_address',
        )
        nmcli_command_manager.set_property_mapping(
            command_property_name = 'GENERAL.HWADDR',
            internal_property_name = 'hardware_address',
        )
        ip_route_ip_address_command_manager.set_property_mapping(
            command_property_name = 'ip_address',
            internal_property_name = 'ipv4_address',
        )
        ip_route_gateway_address_command_manager.set_property_mapping(
            command_property_name = 'default_gateway',
            internal_property_name = 'default_gateway_ipv4_address',
        )
        ip_addr_mac_address_command_manager.set_property_mapping(
            command_property_name = 'hardware_address',
            internal_property_name = 'hardware_address',
        )
        sys_vendor_command_manager.set_property_mapping(
            command_property_name = 'vendor_id',
            internal_property_name = 'vendor_id',
        )
        sys_device_command_manager.set_property_mapping(
            command_property_name = 'device_id',
            internal_property_name = 'device_id',
        )
        # Set up all the parsers
        nmcli_command_manager.set_command_parser(parser = nmcli_parser)
        ip_address_parser = ip_route_ip_address_command_manager.initialize_command_parser(
            parser_type = 'table-row',
        )
        gateway_address_parser = ip_route_gateway_address_command_manager.initialize_command_parser(
            parser_type = 'table-row',
        )
        mac_address_parser = ip_addr_mac_address_command_manager.initialize_command_parser(
            parser_type = 'table-row',
        )
        sys_vendor_parser = sys_vendor_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        sys_device_parser = sys_device_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        ip_address_parser.add_regular_expression(
            regex = '(?P<network_address>\S+)\s+proto\s+(?P<protocol>\S+)\s+'
                + 'scope\s+(?P<scope>\S+)\s+src\s+(?P<ip_address>\S+)',
        )
        ip_address_parser.set_column_titles(
            titles = ['network_address', 'protocol', 'scope', 'ip_address'],
        )
        ip_address_parser.set_specified_row(
            column_title = 'scope',
            column_value = 'link',
        )
        gateway_address_parser.add_regular_expression(
            regex = '(?P<default>default) via (?P<default_gateway>\S+)',
        )
        gateway_address_parser.set_column_titles(
            titles = ['default', 'default_gateway'],
        )
        gateway_address_parser.set_specified_row(
            column_title = 'default',
            column_value = 'default',
        )
        mac_address_parser.add_regular_expression(
            regex = '\d+: (?P<interface_name>\w+): .+?link/ether '
                + '(?P<hardware_address>\S+)',
        )
        mac_address_parser.set_column_titles(
            titles = ['interface_name', 'hardware_address'],
        )
        mac_address_parser.set_specified_row(
            column_title = 'interface_name',
            column_value = self.get_name(),
        )
        sys_vendor_parser.set_export_key(key = 'vendor_id')
        sys_vendor_parser.set_regex(regex = '(0x\w+)')
        sys_device_parser.set_export_key(key = 'device_id')
        sys_device_parser.set_regex(regex = '(0x\w+)')
        # Set all the command priorities
        property_manager.set_command_priority(
            property_name = 'ipv4_address',
            command_priority = ['nmcli', 'ip_route_ip_address'],
        )
        property_manager.set_command_priority(
            property_name = 'default_gateway_ipv4_address',
            command_priority = ['nmcli', 'ip_route_gateway_address'],
        )
        property_manager.set_command_priority(
            property_name = 'hardware_address',
            command_priority = ['nmcli', 'ip_addr_mac_address'],
        )
        property_manager.set_command_priority(
            property_name = 'vendor_id',
            command_priority = ['sys_vendor'],
        )
        property_manager.set_command_priority(
            property_name = 'device_id',
            command_priority = ['sys_device'],
        )

    def enable(self, preferred_command = 'nmcli'):
        """
        Bring the network interface up.

        Keyword arguments:
        preferred_command - Preferred command to use to bring the interface up.

        """
        # If the command to use is nmcli
        if preferred_command == 'nmcli':
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            nmcli.device().connect(interface_name = self.get_name())
        # If the command to use is ip
        elif preferred_command == 'ip':
            ip = self._get_manager().get_command_object(command_name = 'ip')
            ip_link = ip.get_ip_object(object_string = 'link')
            ip_link_set = ip_link.get_command(command_string = 'set')
            ip_link_set.run_command(
                command_arguments = '{0} up'.format(self.get_name()),
            )
        # If the command to use is ifup
        elif preferred_command == 'ifup':
            ifup = self._get_manager().get_command_object(command_name = 'ifup')
            ifup.run_command(interface_name = self.get_name())
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )

    def disable(self, preferred_command = 'nmcli'):
        """
        Bring the network interface down.

        Keyword arguments:
        preferred_command - Preferred command to use to bring the interface
                            down.

        """
        # If the command to use is nmcli
        if preferred_command == 'nmcli':
            nmcli = self._get_manager().get_command_object(
                command_name = 'nmcli',
            )
            nmcli.device().disconnect(interface_name = self.get_name())
        # If the command to use is ip
        elif preferred_command == 'ip':
            ip = self._get_manager().get_command_object(command_name = 'ip')
            ip_link = ip.get_ip_object(object_string = 'link')
            ip_link_set = ip_link.get_command(command_string = 'set')
            ip_link_set.run_command(
                command_arguments = '{0} down'.format(self.get_name()),
            )
        # If the command to use is ifdown
        elif preferred_command == 'ifdown':
            ifdown = self._get_manager().get_command_object(
                command_name = 'ifdown',
            )
            ifdown.run_command(interface_name = self.get_name())
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )

    def request_ipv4_address(self):
        """
        Request an IPv4 address for the network interface.

        """
        dhclient = self._get_manager().get_command_object(
            command_name = 'dhclient',
        )
        output = dhclient.run_command(command_arguments = self.get_name())
        for line in output:
            match = re.search('bound to (?P<ip_address>\S+)', line)
            if match:
                ip_address = match.group('ip_address')
                self.get_property_manager().set_property(
                    property_name = 'ipv4_address',
                    property_value = ip_address,
                )
        self._set_connected()

    def is_destination_reachable(
        self,
        destination,
        timeout = 30,
        minimum_success_count = 1,
        broadcast = False,
        preferred_command = 'ping'
    ):
        """
        Check that the network destination provided is reachable.

        Keyword arguments:
        destination - The destination host.
        timeout - Maximum number of seconds to wait for success.
        minimum_success_count - Number of successes before the destination is
                                deemed reachable.
        broadcast - Enables broadcast mode.
        preferred_command - Preferred command to use to check that the
                            destination provided is reachable.

        Return value:
        True if the destination is reachable. False otherwise.

        """
        destination_reachable = False
        # If the command to use is ping
        if preferred_command == 'ping':
            ping = self._get_manager().get_command_object(command_name = 'ping')
            ping.set_success_regular_expression(
                regex = '{0} received'.format(minimum_success_count),
            )
            command_arguments = ''
            if broadcast:
                command_arguments += '-b '
            command_arguments += '-c {0} '.format(minimum_success_count)
            command_arguments += '-w {0} '.format(timeout)
            command_arguments += '-I {0} '.format(self.get_name())
            command_arguments += destination
            try:
                ping.run_command(command_arguments = command_arguments)
                destination_reachable = True
            except FailedCommandOutputError:
                destination_reachable = False
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )
        return destination_reachable
