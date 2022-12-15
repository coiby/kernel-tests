#!/usr/bin/python
# Copyright (c) 2017 Red Hat, Inc. All rights reserved. This copyrighted material
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
The worknode.linux.util.rhel7.nmcli module provides a class (nmcli) that
represents the nmcli command line executable.

"""

__author__ = 'Ken Benoit'

import worknode.linux.util.nmcli

from worknode.exception.worknode_executable import *

class nmcli(worknode.linux.util.nmcli.nmcli):
    """
    nmcli represents the nmcli command line executable, which provides a command
    line interface to NetworkManager.

    Keyword arguments:
    work_node - WorkNode object.
    command - Name of the command to use. Defaults to 'nmcli'.

    """
    def __init__(self, work_node, command = 'nmcli'):
        super(nmcli, self).__init__(work_node)
        self.__connection = self.connection_manager(
            parent = self,
            object_string = 'connection',
        )
        self.__radio = self.radio_manager(
            parent = self,
            object_string = 'radio',
        )
        self.__device = self.device_manager(
            parent = self,
            object_string = 'device',
        )
        self.__general = self.general_manager(
            parent = self,
            object_string = 'general',
        )

    class base_manager(object):
        """
        base_manager is a generic manager that all sub-managers should inherit
        from.

        Keyword arguments:
        parent - Parent nmcli object.

        """
        def __init__(self, parent, object_string):
            self.__object = parent.add_nmcli_object(
                object_string = object_string,
            )
            self._configure_object()

        def _get_object(self):
            return self.__object

        def _configure_object(self):
            pass

        def get_command(self, command_string, command_arguments = None):
            """
            Get the full command to be executed.

            Keyword arguments:
            command_string - The string that needs to be supplied to the nmcli
                             object to execute the command.
            command_arguments - Argument string to feed to the command.

            Return value:
            Full command to be executed.

            """
            return self.__object.get_command(
                command_string = command_string,
            ).get_command(command_arguments = command_arguments)

        def get_command_parser(self, command_string):
            """
            Get the command parser for the command.

            Keyword arguments:
            command_string - The string that needs to be supplied to the nmcli
                             object to execute the command.

            Return value:
            Parser object (worknode.command_parser)

            """
            return self.__object.get_command(
                command_string = command_string,
            ).get_command_parser()

    def connection(self):
        """
        Get the "nmcli connection" object.

        Return value:
        NmcliObject for the "nmcli connection" command.

        """
        return self.__connection

    class connection_manager(base_manager):
        """
        connection_manager handles all connection methods (creation,
        destruction, status, etc).

        Keyword arguments:
        parent - Parent nmcli object.

        """
        def _configure_object(self):
            # Configure 'connection up'
            nmcli_con_up = self._get_object().add_command(command_string = 'up')
            nmcli_con_up.add_failure_regular_expression(
                regex = 'Connection activation failed',
            )
            # Configure 'connection down'
            nmcli_con_down = self._get_object().add_command(
                command_string = 'down',
            )
            nmcli_con_add = self._get_object().add_command(
                command_string = 'add',
            )
            nmcli_con_add_parser = nmcli_con_add.initialize_command_parser(
                output_type = 'single',
            )
            nmcli_con_add_parser.set_export_key(key = 'UUID')
            nmcli_con_add_parser.set_regex(
                regex = "Connection '.+?' \((\S*)\) successfully added.",
            )
            # Configure 'connection add'
            nmcli_con_add = self._get_object().add_command(
                command_string = 'add',
            )
            nmcli_con_add_parser = nmcli_con_add.initialize_command_parser(
                output_type = 'single',
            )
            nmcli_con_add_parser.set_export_key(key = 'UUID')
            nmcli_con_add_parser.set_regex(
                regex = "Connection '.+?' \((\S*)\) successfully added.",
            )
            # Configure 'connection show'
            nmcli_con_show = self._get_object().add_command(
                command_string = 'show',
            )
            nmcli_con_show.add_option(option_flag = '--terse')
            nmcli_con_show.add_option(
                option_flag = '--fields',
                option_value = 'NAME,UUID,TYPE,TIMESTAMP,AUTOCONNECT,READONLY,'
                    + 'DBUS-PATH',
            )
            nmcli_con_show_parser = nmcli_con_show.initialize_command_parser(
                output_type = 'table',
            )
            nmcli_con_show_parser.set_column_titles(
                titles = [
                    'NAME',
                    'UUID',
                    'TYPE',
                    'TIMESTAMP',
                    'AUTOCONNECT',
                    'READONLY',
                    'DBUS_PATH',
                ],
            )
            nmcli_con_show_parser.add_regular_expression(
                regex = '(?P<NAME>.+):(?P<UUID>\S+):(?P<TYPE>\S+):'
                    + '(?P<TIMESTAMP>\S+):(?P<AUTOCONNECT>\S+):'
                    + '(?P<READONLY\S+):(?P<DBUS_PATH>\S+)\n',
            )
            # Configure 'connection delete'
            nmcli_con_delete = self._get_object().add_command(
                command_string = 'delete',
            )
            # Configure 'connection modify'
            nmcli_con_modify = self._get_object().add_command(
                command_string = 'modify',
            )

        def bring_up_connection(self, name = None, uuid = None):
            """
            Bring up the connection indicated.

            Keyword arguments:
            name - Name of the connection (optional if uuid is provided
                   instead).
            uuid - UUID of the connection (optional if name is provided
                   instead).

            """
            if name is None and uuid is None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid"
                )
            if name is not None and uuid is not None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid, not both"
                )
            nmcli_con_up = self._get_object().get_command(command_string = 'up')
            id_string = ''
            if name is not None:
                id_string = 'id {name}'.format(name = name)
            else:
                id_string = 'uuid {uuid}'.format(uuid = uuid)
            nmcli_con_up.run_command(
                command_arguments = id_string,
                timeout = 60,
            )

        def bring_down_connection(self, name = None, uuid = None):
            """
            Bring down the connection indicated.

            Keyword arguments:
            name - Name of the connection (optional if uuid is provided
                   instead).
            uuid - UUID of the connection (optional if name is provided
                   instead).

            """
            if name is None and uuid is None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid"
                )
            if name is not None and uuid is not None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid, not both"
                )
            nmcli_con_down = self._get_object().get_command(
                command_string = 'down',
            )
            if name is not None:
                id_string = 'id {name}'.format(name = name)
            else:
                id_string = 'uuid {uuid}'.format(uuid = uuid)
            nmcli_con_down.run_command(
                command_arguments = id_string,
                timeout = 60,
            )

        def set_ipv4_address_of_connection(
            self,
            name = None,
            uuid = None,
            ip_address = None,
        ):
            """
            Set the IPv4 address of the indicated connection.

            Keyword arguments:
            name - Name of the connection (optional if uuid is provided
                   instead).
            uuid - UUID of the connection (optional if name is provided
                   instead).
            ip_address - IP address (with subnet mask) to use when setting the
                         connection (optional if you want the connection to use
                         DHCP).

            """
            if name is None and uuid is None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid"
                )
            if name is not None and uuid is not None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid, not both"
                )
            connection_id = None
            if name is not None:
                connection_id = 'id "{name}"'.format(name = name)
            else:
                connection_id = 'uuid {uuid}'.format(uuid = uuid)
            ip_address_arguments = None
            if ip_address is None:
                ip_address_arguments = 'ipv4.method auto'
            else:
                ip_address_arguments = \
                    'ipv4.method manual ipv4.addresses {ip_address}'.format(
                        ip_address = ip_address
                    )
            nmcli_con_modify = self._get_object().get_command(
                command_string = 'modify',
            )
            nmcli_con_modify.run_command(
                command_arguments = ' '.join(
                    [connection_id, ip_address_arguments]
                ),
            )

        def set_ipv6_address_of_connection(
            self,
            name = None,
            uuid = None,
            ip_address = None,
        ):
            """
            Set the IPv6 address of the indicated connection.

            Keyword arguments:
            name - Name of the connection (optional if uuid is provided
                   instead).
            uuid - UUID of the connection (optional if name is provided
                   instead).
            ip_address - IP address (with subnet mask) to use when setting the
                         connection (optional if you want the connection to use
                         DHCP).

            """
            if name is None and uuid is None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid"
                )
            if name is not None and uuid is not None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid, not both"
                )
            connection_id = None
            if name is not None:
                connection_id = 'id "{name}"'.format(name = name)
            else:
                connection_id = 'uuid {uuid}'.format(uuid = uuid)
            ip_address_arguments = None
            if ip_address is None:
                ip_address_arguments = 'ipv6.method auto'
            else:
                ip_address_arguments = \
                    'ipv6.method manual ipv6.addresses {ip_address}'.format(
                        ip_address = ip_address
                    )
            nmcli_con_modify = self._get_object().get_command(
                command_string = 'modify',
            )
            nmcli_con_modify.run_command(
                command_arguments = ' '.join(
                    [connection_id, ip_address_arguments]
                ),
            )

        def create_wireless_connection(
            self,
            interface_name,
            ssid,
            name = None,
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
            retries = None,
        ):
            """
            Configure and connect to a wireless network.

            Keyword arguments:
            ssid - SSID of the wireless network.
            name - Name of the network connection.
            key_management - Type of key management to use (none, 8021x,
                             wpa-psk, wpa-eap).
            pairwise - Pairwise encryption algorithm to use (tkip, ccmp).
            group - Group encryption algorithm to use (wep40, wep104, tkip,
                    ccmp).
            proto - WPA protocol to use (wpa, rsn).
            psk - Pre-shared key for WPA network.
            eap - EAP method to use when authenticating (leap, md5, tls, ttls).
            identity - Identity string for authentication.
            ca_cert - Path to the CA certificate for EAP authentication.
            client_cert - Path to the client certificate for EAP authentication.
            private_key - Path to the private key for TLS EAP authentication.
            private_key_password - Password to decrypt the private key provided
                                   in private_key.
            auth_alg - Authentication algorithm required by a WEP AP.
            password - Password string for authentication.
            phase2_autheap - Specifies the allowed 'phase 2' inner EAP-based
                             authentication methods when an EAP method that uses
                             an inner TLS tunnel is specified in the 'eap'
                             property.
            wep_key_type - 1 if WEP key is hexadecimal or ASCII, 2 if WEP key
                           MD5 hashed passphrase.
            wep_key0 - Index 0 WEP key.
            wep_key1 - Index 1 WEP key.
            wep_key2 - Index 2 WEP key.
            wep_key3 - Index 3 WEP key.
            hidden - If True then the wireless network being connected to does
                     not broadcast its SSID.
            ipv4_address - IPv4 address to assign to the connection (with subnet
                           mask).
            ipv6_address - IPv6 address to assign to the connection (with subnet
                           mask).
            retries - Number of times to re-attempt to bring up the wireless
                      connection if the first try fails.

            Return value:
            String of the UUID of the created connection.

            """
            con_add = self._get_object().get_command(command_string = 'add')
            con_modify = self._get_object().get_command(
                command_string = 'modify',
            )

            con_add_arguments = 'type wifi ifname {0}'.format(interface_name)
            if name is not None:
                con_add_arguments += ' con-name "{0}"'.format(name)
            con_add_arguments += ' ssid "{0}"'.format(ssid)
            add_parsed_output = con_add.run_command(
                command_arguments = con_add_arguments,
            )
            uuid = add_parsed_output['UUID']
            con_modify_base_arguments = 'uuid {0} '.format(uuid)
            con_modify_additional_arguments = []

            # Perform the modifications for the specifics
            if key_management is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.key-mgmt "{0}"'.format(
                        key_management,
                    ),
                )
            if pairwise is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.pairwise {0}'.format(pairwise),
                )
            if group is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.group {0}'.format(group),
                )
            if proto is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.proto {0}'.format(proto),
                )
            if psk is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.psk "{0}"'.format(psk),
                )
            if eap is not None:
                con_modify_additional_arguments.append(
                    '802-1x.eap {0}'.format(eap),
                )
            if ca_cert is not None:
                con_modify_additional_arguments.append(
                    '802-1x.ca-cert "{0}"'.format(ca_cert),
                )
            if client_cert is not None:
                con_modify_additional_arguments.append(
                    '802-1x.client-cert "{0}"'.format(client_cert),
                )
            if private_key_password is not None:
                con_modify_additional_arguments.append(
                    '802-1x.private-key-password "{0}"'.format(
                        private_key_password,
                    ),
                )
            if private_key is not None:
                con_modify_additional_arguments.append(
                    '802-1x.private-key "{0}"'.format(private_key),
                )
            if auth_alg is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.auth-alg {0}'.format(auth_alg),
                )
                if auth_alg.lower() == 'leap':
                    if identity is not None:
                        con_modify_additional_arguments.append(
                            '802-11-wireless-security.leap-username '
                                + '"{0}"'.format(
                                    identity,
                                ),
                        )
                    if password is not None:
                        con_modify_additional_arguments.append(
                            '802-11-wireless-security.leap-password '
                                + '"{0}"'.format(
                                    password,
                                ),
                        )
            if identity is not None:
                con_modify_additional_arguments.append(
                    '802-1x.identity "{0}"'.format(identity),
                )
            if password is not None:
                con_modify_additional_arguments.append(
                    '802-1x.password "{0}"'.format(password),
                )
            if phase2_autheap is not None:
                con_modify_additional_arguments.append(
                    '802-1x.phase2-autheap {0}'.format(phase2_autheap),
                )
            if wep_key_type is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.wep-key-type "{0}"'.format(
                        wep_key_type,
                    ),
                )
            if wep_key0 is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.wep-key0 "{0}"'.format(wep_key0),
                )
            if wep_key1 is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.wep-key1 "{0}"'.format(wep_key1),
                )
            if wep_key2 is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.wep-key2 "{0}"'.format(wep_key2),
                )
            if wep_key3 is not None:
                con_modify_additional_arguments.append(
                    '802-11-wireless-security.wep-key3 "{0}"'.format(wep_key3),
                )
            if hidden:
                con_modify_additional_arguments.append(
                    '802-11-wireless.hidden yes',
                )
            if con_modify_additional_arguments != []:
                con_modify.run_command(
                    command_arguments = con_modify_base_arguments
                        + ' '.join(con_modify_additional_arguments),
                )
            # Configure the IPv4 address of the connection
            self.set_ipv4_address_of_connection(
                uuid = uuid,
                ip_address = ipv4_address,
            )
            # Configure the IPv6 address of the connection
            self.set_ipv6_address_of_connection(
                uuid = uuid,
                ip_address = ipv6_address,
            )
            if retries is None:
                self.bring_up_connection(uuid = uuid)
            else:
                current = 0
                while current < retries:
                    try:
                        self.bring_up_connection(uuid = uuid)
                        break
                    except FailedCommandOutputError as e:
                        current += 1
                        if current == retries:
                            raise e

            return uuid

        def create_ibss_connection(
            self,
            interface_name,
            ssid,
            name = None,
            channel = None,
            band = None,
            ipv4_address = None,
            ipv6_address = None,
        ):
            """
            Configure and connect to a wireless ad-hoc (IBSS) network.

            Keyword arguments:
            ssid - SSID of the IBSS connection.
            name - Name of the network connection.
            channel - 802.11 channel to use for the IBSS connection.
            ipv4_address - IPv4 address to assign to the connection (with subnet
                           mask).
            ipv6_address - IPv6 address to assign to the connection (with subnet
                           mask).

            Return value:
            String of the UUID of the created connection.

            """
            # Map out the 802.11 channels to the name of the band they belong to
            channel_band_map = {
                'bg': {
                    'start': 1,
                    'end': 14,
                },
                'a': {
                    'start': 36,
                    'end': 165,
                },
            }
            band = None
            # Figure out if the wireless band we're operating in is either "bg"
            # (2.4GHz) or "a" (5GHz)
            for band_name in channel_band_map.keys():
                if int(channel) >= channel_band_map[band_name]['start'] and \
                    int(channel) <= channel_band_map[band_name]['end']:
                    band = band_name
                    break
            # Build the "nmcli connection add" command
            con_add = self._get_object().get_command(command_string = 'add')
            con_add_arguments = 'type wifi ifname {0}'.format(interface_name)
            if name is not None:
                con_add_arguments += ' con-name "{0}"'.format(name)
            con_add_arguments += ' ssid "{0}" mode adhoc'.format(ssid)
            # Run the "nmcli connection add" command
            add_parsed_output = con_add.run_command(
                command_arguments = con_add_arguments,
            )
            # Grab the UUID of the connection that was just created
            uuid = add_parsed_output['UUID']
            # Build the "nmcli connection modify" command
            con_modify = self._get_object().get_command(
                command_string = 'modify',
            )
            con_modify_base_arguments = 'uuid {0} '.format(uuid)
            con_modify_additional_arguments = []
            if channel is not None:
                con_modify_additional_arguments.append(
                    "802-11-wireless.channel {}".format(channel)
                )
            if band is not None:
                con_modify_additional_arguments.append(
                    "802-11-wireless.band {}".format(band)
                )
            if con_modify_additional_arguments != []:
                # Run the "nmcli connection modify" command
                con_modify.run_command(
                    command_arguments = con_modify_base_arguments
                        + ' '.join(con_modify_additional_arguments),
                )
            # Configure the IPv4 address of the connection
            self.set_ipv4_address_of_connection(
                uuid = uuid,
                ip_address = ipv4_address,
            )
            # Configure the IPv6 address of the connection
            self.set_ipv6_address_of_connection(
                uuid = uuid,
                ip_address = ipv6_address,
            )
            self.bring_up_connection(uuid = uuid)
            return uuid

        def delete_connection(self, name = None, uuid = None):
            """
            Delete the connection indicated.

            Keyword arguments:
            name - Name of the connection (optional if uuid is provided
                   instead).
            uuid - UUID of the connection (optional if name is provided
                   instead).

            """
            if name is None and uuid is None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid"
                )
            if name is not None and uuid is not None:
                raise CommandArgumentsError(
                    "Need to be provided either name or uuid, not both"
                )
            con_delete = self._get_object().get_command(
                command_string = 'delete',
            )
            if name is not None:
                con_delete.run_command(
                    command_arguments = 'id {name}'.format(
                        name = name,
                    )
                )
            else:
                con_delete.run_command(
                    command_arguments = 'uuid {uuid}'.format(
                        uuid = uuid,
                    )
                )

    def radio(self):
        """
        Get the "nmcli radio" object.

        Return value:
        NmcliObject for the "nmcli radio" command.

        """
        return self.__radio

    class radio_manager(base_manager):
        """
        radio_manager handles all radio methods (enable, disable, status, etc).

        Keyword arguments:
        parent - Parent nmcli object.

        """
        def _configure_object(self):
            # Configure 'nmcli radio wifi'
            radio_wifi = self._get_object().add_command(command_string = 'wifi')
            nmcli_radio_wifi_parser = radio_wifi.initialize_command_parser(
                output_type = 'single',
            )
            nmcli_radio_wifi_parser.set_export_key(key = 'radio_status')
            nmcli_radio_wifi_parser.set_regex(regex = '(\S*)')
            # Configure 'nmcli radio wwan'
            radio_wwan = self._get_object().add_command(command_string = 'wwan')
            nmcli_radio_wwan_parser = radio_wwan.initialize_command_parser(
                output_type = 'single',
            )
            nmcli_radio_wwan_parser.set_export_key(key = 'radio_status')
            nmcli_radio_wwan_parser.set_regex(regex = '(\S*)')

        def enable_wifi_radio(self):
            """
            Enable the radio for the wireless (802.11).

            """
            radio_wifi = self._get_object().get_command(command_string = 'wifi')
            radio_wifi.run_command(command_arguments = 'on')

        def disable_wifi_radio(self):
            """
            Disable the radio for the wireless (802.11).

            """
            radio_wifi = self._get_object().get_command(command_string = 'wifi')
            radio_wifi.run_command(command_arguments = 'off')

        def is_wifi_radio_enabled(self):
            """
            Check if the wifi radio is currently enabled.

            Return value:
            True if the wifi radio is currently enabled. False if the wifi radio
            is currently disabled.

            """
            radio_wifi = self._get_object().get_command(command_string = 'wifi')
            radio_status = radio_wifi.run_command()
            if radio_status['radio_status'] == 'enabled':
                return True
            elif radio_status['radio_status'] == 'disabled':
                return False
            else:
                raise FailedCommandOutputError(
                    "Unknown if the wireless radio is enabled"
                )

        def enable_wwan_radio(self):
            """
            Enable the radio for the wireless wide area network (wireless
            broadband).

            """
            radio_wifi = self._get_object().get_command(command_string = 'wwan')
            radio_wifi.run_command(command_arguments = 'on')

        def disable_wwan_radio(self):
            """
            Disable the radio for the wireless wide area network (wireless
            broadband).

            """
            radio_wifi = self._get_object().get_command(command_string = 'wwan')
            radio_wifi.run_command(command_arguments = 'off')

        def is_wwan_radio_enabled(self):
            """
            Check if the wireless wide area network radio is currently enabled.

            Return value:
            True if the wireless wide area network radio is currently enabled.
            False if the wireless wide area network radio is currently disabled.

            """
            radio_wwan = self._get_object().get_command(command_string = 'wwan')
            radio_status = radio_wwan.run_command()
            if radio_status['radio_status'] == 'enabled':
                return True
            elif radio_status['radio_status'] == 'disabled':
                return False
            else:
                raise FailedCommandOutputError(
                    "Unknown if the wireless wide area network radio is enabled"
                )

    def device(self):
        """
        Get the "nmcli device" object.

        Return value:
        NmcliObject for the "nmcli device" command.

        """
        return self.__device

    class device_manager(base_manager):
        """
        device_manager handles all device methods (status, info, modify, etc).

        Keyword arguments:
        parent - Parent nmcli object.

        """
        def _configure_object(self):
            # Configure 'nmcli device status'
            dev_status = self._get_object().add_command(
                command_string = 'status',
            )
            dev_status.add_option(option_flag = '--terse')
            dev_status.add_option(
                option_flag = '--fields',
                option_value = 'DEVICE,TYPE,STATE',
            )
            nmcli_dev_status_parser = dev_status.initialize_command_parser(
                output_type = 'table',
            )
            nmcli_dev_status_parser.set_column_titles(
                titles = ['DEVICE', 'TYPE', 'STATE'],
            )
            nmcli_dev_status_parser.add_regular_expression(
                regex = '(?P<DEVICE>\S+):(?P<TYPE>\S+):(?P<STATE>\S+)',
            )
            # Configure 'nmcli device show'
            dev_show = self._get_object().add_command(
                command_string = 'show',
            )
            dev_show.add_option(option_flag = '--terse')
            dev_show.add_option(
                option_flag = '--fields',
                option_value = ','.join(
                    [
                        'GENERAL', 'CAPABILITIES', 'BOND', 'VLAN',
                        'CONNECTIONS', 'WIFI-PROPERTIES', 'AP',
                        'WIRED-PROPERTIES', 'IP4', 'DHCP4', 'IP6', 'DHCP6',
                    ]
                ),
            )
            nmcli_dev_show_parser = dev_show.initialize_command_parser(
                output_type = 'key-value',
            )
            nmcli_dev_show_parser.add_regular_expression(
                regex = '(?P<property_key>\S+?):(?P<property_value>.+)\n',
            )
            # Configure 'nmcli device wifi connect'
            dev_wifi_connect = self._get_object().add_command(
                command_string = 'wifi connect',
            )
            # Configure 'nmcli device connect'
            dev_connect = self._get_object().add_command(
                command_string = 'connect',
            )
            # Configure 'nmcli device disconnect'
            dev_disconnect = self._get_object().add_command(
                command_string = 'disconnect',
            )

        def show_details(self, interface_name):
            """
            Show details for the specified interface.

            Keyword arguments:
            interface_name - Name of the network interface.

            Return value:
            Output parsed into a dictionary.

            """
            dev_show = self._get_object().get_command(command_string = 'show')
            return dev_show.run_command(command_arguments = interface_name)

        def connect(self, interface_name):
            """
            Connect the specified interface.

            Keyword arguments:
            interface_name - Name of the network interface.

            """
            dev_connect = self._get_object().get_command(
                command_string = 'connect'
            )
            dev_connect.run_command(command_arguments = interface_name)

        def disconnect(self, interface_name):
            """
            Disconnect the specified interface.

            Keyword arguments:
            interface_name - Name of the network interface.

            """
            dev_disconnect = self._get_object().get_command(
                command_string = 'disconnect'
            )
            dev_disconnect.run_command(command_arguments = interface_name)

    def general(self):
        """
        Get the "nmcli general" object.

        Return value:
        NmcliObject for the "nmcli general" command.

        """
        return self.__general

    class general_manager(base_manager):
        """
        general_manager handles all general methods (status, permissions,
        logging, etc).

        Keyword arguments:
        parent - Parent nmcli object.

        """
        def _configure_object(self):
            # Configure 'nmcli general logging'
            nmcli_gen_logging = self._get_object().add_command(
                command_string = 'logging',
            )

        def set_logging(self, level = 'TRACE', domains = ['ALL']):
            """
            Set the logging to use for NetworkManager.

            Keyword arguments:
            level - Logging level (from least logging to most logging: OFF, ERR,
                    WARN, INFO, DEBUG, TRACE).
            domains - A list of domains to log for (Refer to NetworkManager.conf
                      for a list of possible domains).

            """
            gen_logging = self._get_object().get_command(
                command_string = 'logging'
            )
            gen_logging.run_command(
                command_arguments = 'level {level} domains {domains}'.format(
                    level = level.upper(),
                    domains = ','.join([domain.upper() for domain in domains]),
                )
            )
