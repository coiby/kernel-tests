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

import scapy.all
import subprocess
import json
import re

import base.test
import worknode.worknode_factory
from base.exception.test import *

class BeaconSimulator(base.test.Test):
    def __init__(self):
        super(BeaconSimulator, self).__init__()
        self.__count = None
        self.__number_of_ssids = None
        self.__increment_bssid = None
        self.__starting_bssid = None
        self.__increment_source = None
        self.__starting_source = None
        self.__interface = None
        self.__force = None
        self.__dry_run = None
        self.__address_length = 6
        self.__work_node = None
        self.__allowed_systems_file = 'allowed_systems.json'
        self.__configure_parser()
        self.__configure_test_steps()

        self.set_test_name(
            name = '/kernel/wireless_tests/utility/beacon_simulator',
        )
        self.set_test_author(name = 'Ken Benoit', email = 'kbenoit@redhat.com')
        self.set_test_description(
            description = 'Simulate wireless access points by sending wireless '
                + 'beacon packets.',
        )

    def __configure_test_steps(self):
        self.add_test_step(
            test_step = self.__get_work_node,
        )
        self.add_test_step(
            test_step = self.__set_simulator_internal_arguments,
        )
        self.add_test_step(
            test_step = self.__check_for_allowed_system,
            test_step_description = 'Check if the work node is allowed to run '
                + 'this script.',
        )
        self.add_test_step(
            test_step = self.__find_wireless_interface,
            test_step_description = 'Find the wireless interface to use on the '
                + 'work node.',
        )
        self.add_test_step(
            test_step = self.__simulate_beacons,
            test_step_description = 'Simulate the requested number of wireless '
                + 'beacons.',
        )

    def __configure_parser(self):
        self.add_command_line_option(
            '--count',
            dest = 'count',
            action = 'store',
            type = 'int',
            default = 20,
            help = 'number of times to send out the beacon packet for an '
                + 'individual SSID',
        )
        self.add_command_line_option(
            '--number_of_ssids',
            dest = 'number_of_ssids',
            action = 'store',
            type = 'int',
            default = 1,
            help = 'number of SSIDs to advertise',
        )
        self.add_command_line_option(
            '--increment_bssid',
            dest = 'increment_bssid',
            action = 'store_true',
            default = False,
            help = 'increment the BSSID for each SSID advertised',
        )
        self.add_command_line_option(
            '--starting_bssid',
            dest = 'starting_bssid',
            action = 'store',
            default = '00:00:00:00:00:01',
            help = 'starting BSSID to use',
        )
        self.add_command_line_option(
            '--increment_source',
            dest = 'increment_source',
            action = 'store_true',
            default = False,
            help = 'increment the source MAC address for each SSID advertised',
        )
        self.add_command_line_option(
            '--starting_source',
            dest = 'starting_source',
            action = 'store',
            default = '00:00:00:00:00:01',
            help = 'starting source MAC address to use',
        )
        self.add_command_line_option(
            '--interface',
            dest = 'interface',
            action = 'store',
            default = None,
            help = 'interface to send the beacon packets through (interface '
                'needs to be in monitor mode beforehand)',
        )
        self.add_command_line_option(
            '--force',
            dest = 'force',
            action = 'store_true',
            default = False,
            help = 'force this script to run in an environment that isn\'t'
                + ' recommended',
        )

    def __get_work_node(self):
        self.work_node = worknode.worknode_factory.WorkNodeFactory().get_work_node()

    def __check_for_allowed_system(self):
        allowed_systems = {}
        block_content_names = [
            'name_type',
            'regex',
            'name_list',
        ]
        system_allowed = False
        # Try to open the allowed systems json file
        try:
            allowed_systems_file = open(self.__allowed_systems_file)
            allowed_systems = json.load(allowed_systems_file)
            allowed_systems_file.close()
        # If we can't find/open the file then log the error but continue
        except IOError:
            self.get_logger().error(
                "Unable to locate {0} file".format(self.__allowed_systems_file)
            )
        # Go through the allowed systems definitions
        for block_name, block_contents in allowed_systems.items():
            # Make sure we have all the attribute names defined
            for name in block_content_names:
                if name not in block_contents:
                    raise Exception(
                        'Block "{0}" is missing the "{1}" attribute'.format(
                            block_name,
                            name,
                        )
                    )
            allowed_name = None
            # If a 'hostname' type then get the hostname
            if block_contents['name_type'] == 'hostname':
                allowed_name = self.work_node.get_hostname()
            # If a 'dnsdomainname' type then get the DNS domain name
            elif block_contents['name_type'] == 'dnsdomainname':
                allowed_name = self.work_node.get_dns_domain_name()
            # We don't know what anything else is
            else:
                raise Exception(
                    'Unknown "name_type" attribute value "{0}" in block "{1}"'.format(
                        block_contents['name_type'],
                        block_name,
                    )
                )
            # Go through each of the names in the 'name_list'
            for match_name in block_contents['name_list']:
                # If we're doing a regular expression match
                if block_contents['regex']:
                    if re.search(match_name, allowed_name):
                        system_allowed = True
                        break
                # If we're doing an exact match
                else:
                    if match_name == allowed_name:
                        system_allowed = True
                        break
            # Break out early if we found a match
            if system_allowed:
                break
        # Report if we didn't find a match, even if we're forcing the script to
        # run
        if self.__force and not system_allowed:
            self.get_logger().info(
                "System does not appear to be allowed to run this script but "
                + "we're forcing the script to run"
            )
        # Raise an exception if we didn't find a match and we're not forcing the
        # script to run
        elif not self.__force and not system_allowed:
            raise TestFailure(
                "System does not appear to be allowed to to run this script "
                + "and is not being forced to run"
            )

    def __set_simulator_internal_arguments(self):
        self.__count = self.get_command_line_option_value(
            dest = 'count',
        )
        self.__number_of_ssids = self.get_command_line_option_value(
            dest = 'number_of_ssids',
        )
        self.__increment_bssid = self.get_command_line_option_value(
            dest = 'increment_bssid',
        )
        self.__starting_bssid = self.get_command_line_option_value(
            dest = 'starting_bssid',
        )
        self.__increment_source = self.get_command_line_option_value(
            dest = 'increment_source',
        )
        self.__starting_source = self.get_command_line_option_value(
            dest = 'starting_source',
        )
        self.__force = self.get_command_line_option_value(
            dest = 'force',
        )

    def __find_wireless_interface(self):
        network_manager = self.work_node.get_network_component_manager()
        interfaces = network_manager.get_wireless_interfaces()
        test_interface_argument = self.get_command_line_option_value(
            dest = 'interface',
        )
        if len(interfaces) == 0:
            raise TestFailure("Unable to locate any wireless interfaces")
        if test_interface_argument is None:
            random = self.get_random_module()
            self.__interface = random.choice(interfaces)
        else:
            self.__interface = network_manager.get_interface(
                interface_name = test_interface_argument,
            )
        self.get_logger().info("Chosen wireless interface: {0}".format(self.__interface.get_name()))

    def __generate_hex_address_list(self, name, starting_address, number_of_addresses, increment):
        hex_string_address_list = []
        # Split out the string version of the starting address
        string_octets = starting_address.split(':')
        # Check to make sure we have the proper number of octets
        if len(string_octets) != self.__address_length:
            raise Exception(
                "{0} needs an address made of {1} octets".format(
                    name,
                    self.__address_length,
                )
            )
        int_octets = []
        # Generate an array of the integer versions of the octets
        for octet in string_octets:
            int_octet = None
            try:
                # Do the conversion from a hex string to an integer value
                int_octet = int(octet, 16)
            except ValueError:
                # Throw an exception if the value is not a hex string
                raise ValueError(
                    "Octet '{0}' in {1} needs to be base 16".format(octet, name)
                )
            if (int_octet < 0) or (int_octet > 255):
                # Throw an exception if the value is not between 0x00 and 0xff
                raise ValueError(
                    "Octet '{0}' in {1} needs to be a value ".format(octet, name)
                    + "between 0x00 and 0xff (inclusively)"
                )
            int_octets.append(int(octet, 16))
        # Generate the list of hex string addresses
        for i in range(number_of_addresses):
            string_address = "{0:02x}:{1:02x}:{2:02x}:{3:02x}:{4:02x}:{5:02x}".format(
                int_octets[0],
                int_octets[1],
                int_octets[2],
                int_octets[3],
                int_octets[4],
                int_octets[5],
            )
            hex_string_address_list.append(string_address)
            # If we are meant to increment the address, then do so now
            if increment:
                # First reverse the list of octets
                int_octets.reverse()
                for index in range(len(int_octets)):
                    # If an octet is 255 then increment it to 0, continue to
                    # roll into the next octet
                    if int_octets[index] == 255:
                        int_octets[index] = 0
                    # If the octet isn't 255 then increment it by 1 and stop
                    else:
                        int_octets[index] += 1
                        break
                # Bring the list of octets back to original order
                int_octets.reverse()
        return hex_string_address_list

    def __generate_ssid_list(self, number_of_ssids, name_prefix = 'testing'):
        ssid_names = []
        for i in range(number_of_ssids):
            ssid_names.append("{0}{1}".format(name_prefix, i))
        return ssid_names

    def __send_beacon_packet(self, ssid, bssid, source_address):
        beacon = scapy.all.Dot11Beacon(cap = 0x2104)
        essid = scapy.all.Dot11Elt(ID = 'SSID', info = ssid)
        rates = scapy.all.Dot11Elt(ID = 'Rates', info = '\x03\x12\x96\x18\x24\x30\x48\x60')
        dsset = scapy.all.Dot11Elt(ID = 'DSset', info = '\x01')
        tim = scapy.all.Dot11Elt(ID = 'TIM', info = '\x00\x01\x00\x00')
        packet = scapy.all.RadioTap()\
            /scapy.all.Dot11(type = 0, subtype = 8, addr1 = 'ff:ff:ff:ff:ff:ff', addr2 = source_address, addr3 = bssid)\
            /beacon/essid/rates/dsset/tim
        self.get_logger().info(
            "Sending beacon packet through interface {0}: SSID {1}; BSSID {2}; source address {3}".format(
                self.__interface.get_name(),
                ssid,
                bssid,
                source_address
            )
        )
        # Sending the packet without the 'inter' argument so that there is no
        # artificial flow control. This does cause there to be a massive packet
        # storm but it's the only way to have enough packets in the air at once
        # for a receiver to find the number of SSIDs specified.
        scapy.all.sendp(
            packet,
            iface = self.__interface.get_name(),
            count = 1,
            #inter = 0.1
            verbose = 0,
        )

    def __simulate_beacons(self):
        bssid_list = self.__generate_hex_address_list(
            name = 'BSSID',
            starting_address = self.__starting_bssid,
            number_of_addresses = self.__number_of_ssids,
            increment = self.__increment_bssid,
        )
        source_list = self.__generate_hex_address_list(
            name = 'source address',
            starting_address = self.__starting_source,
            number_of_addresses = self.__number_of_ssids,
            increment = self.__increment_source,
        )
        ssid_names = self.__generate_ssid_list(
            number_of_ssids = self.__number_of_ssids,
        )
        for count_number in range(self.__count):
            self.get_logger().info("Packet count per SSID: {0}".format(count_number + 1))
            for index in range(len(ssid_names)):
                self.__send_beacon_packet(
                    ssid = ssid_names[index],
                    bssid = bssid_list[index],
                    source_address = source_list[index],
                )

if __name__ == '__main__':
    exit(BeaconSimulator().run_test())
