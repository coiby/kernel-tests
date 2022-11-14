#!/usr/bin/python3
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
The flask_system module provides a class (System) that provides REST API methods
to setup and teardown wireless ad-hoc connections.

"""

__author__ = 'Ken Benoit'

import flask
import re
import subprocess
import operator

app = flask.Flask(__name__)

class System(object):
    """
    System object represents a general command container that represents the
    test system itself. It has some methods to ease gathering certain data from
    the system.

    """
    def __init__(self):
        self.__connection_name = 'test-ad-hoc-con'

    def get_connection_name(self):
        """
        Get the name of the ad-hoc connection in NetworkManager.

        Return value:
        String of the name of the connection.

        """
        return self.__connection_name

    def get_available_wireless_interface_name(self):
        """
        Get the name of the wireless interface on the system (or one of the
        currently unused wireless interfaces if multiple are present).

        Return value:
        String of an unused wireless interface.

        """
        interface_name = None
        output = self._run_command(command = 'nmcli dev status')
        output = output.split('\n')
        if len(output) > 1:
            for line in output[1:]:
                match = re.search(
                    "(?P<interface_name>\S+)\s+wifi\s+disconnected",
                    line
                )
                if match:
                    # Once we find a wireless interface that is disconnected
                    # make sure we save off the name and immediately break out
                    # of the for loop
                    interface_name = match.group('interface_name')
                    break
        return interface_name

    def get_available_channels(self):
        """
        Get a list of wireless channels the wireless card is capable of
        supporting.

        Return values:
        List of available wireless channels (sorted from least used to most
        used).

        """
        channels = []
        in_use_channels = {}
        interface_name = self.get_available_wireless_interface_name()
        # We need to know the phy name of the wireless interface so grab this
        # from sysfs
        phy_name = self._run_command(
            command = 'cat /sys/class/net/{0}/phy80211/name'.format(
                interface_name,
            )
        ).rstrip()
        # Now that we know the phy name we can query iw for all the information
        # about the wireless interface
        output = self._run_command(command = 'iw {0} info'.format(phy_name))
        output_lines = output.split("\n")
        for line_number in range(0, len(output_lines)):
            line = output_lines[line_number]
            # We just want the channel number so look for output lines that read
            # like "2412 MHz [1] (22.0 dBm)" for example. The channel number is
            # the number in the square brackets so grab that. This regular
            # expression will also avoid channels that are followed by "(no IR)"
            # since these channels cannot be used for creating a connection,
            # only for connecting to an already established connection (IR
            # stands for "initiate radiation").
            match = re.search("\d+ MHz \[(\d+)\] \(\d+\.\d+ dBm\)$", line)
            if match:
                # We also want to make sure that the channel is not followed by
                # a line saying that it is a DFS channel since DFS channels
                # cover a range that that is shared with radar systems. DFS will
                # select a frequency from the DFS range that does not interfere
                # radar systems automatically. You should never use a DFS
                # channel specifically.
                if not re.search("DFS", output_lines[line_number + 1]):
                    channel = int(match.group(1))
                    in_use_channels[channel] = 0
        output = self._run_command(
            command = 'iw {0} scan'.format(interface_name)
        )
        for line in output.split("\n"):
            match = re.search("DS Parameter set: channel (\d+)", line)
            if match:
                channel = int(match.group(1))
                if channel in in_use_channels:
                    in_use_channels[channel] += 1
        sorted_channels = sorted(
            in_use_channels.items(), key = operator.itemgetter(1)
        )
        for channel_tuple in sorted_channels:
            channels.append(channel_tuple[0])
        return channels

    def _run_command(self, command):
        """
        Run the supplied command on the system.

        Keyword arguments:
        command - Command to execute.

        Return value:
        String of output from the executed command.

        """
        print("Command: {0}".format(command))
        try:
            output = subprocess.check_output(
                command,
                shell = True,
                stderr = subprocess.STDOUT,
                universal_newlines = True,
            )
            print("Output: {0}".format(output))
            return output
        except subprocess.CalledProcessError as command_exception:
            print("Error code: {0}".format(command_exception.returncode))
            print("Output: {0}".format(command_exception.output))
            return command_exception.output

    def _adhoc_connection_exists(self):
        output = self._run_command(command = 'nmcli con show')
        output = output.split('\n')
        # Regular expression pattern for searching for an ad-hoc connection that
        # has already been created, in this case "test-ad-hoc-con <a UUID>
        # 802-11-wireless"
        pattern = "^{0}\s+\S+\s+802-11-wireless".format(
            self.get_connection_name()
        )
        for line in output[1:]:
            if re.search(pattern, line):
                return True
        return False

    def _nmcli_error_exists(self, output):
        error_exists = False
        if re.search("^Error: ", output):
            error_exists = True
        return error_exists

system = System()

def write_json_error(error_message):
    """
    Generate an error message in the JSON format.

    Keyword arguments:
    error_message - Error message to include.

    Return values:
    JSONified version of the error message.

    """
    return flask.jsonify(
        {
            'error': error_message,
        }
    )

@app.route('/adhoc_server/get_available_channels/', methods=['GET'])
@app.route('/adhoc_server/get_available_channels', methods=['GET'])
def get_available_channels():
    """
    Get a list of wireless channels that the card can operate on.

    Return value:
    JSON object with a list of wireless channels.

    """
    channels = system.get_available_channels()
    return flask.jsonify(
        {
            'channels': channels,
        }
    )

@app.route('/adhoc_server/setup_adhoc_server/', methods=['PUT', 'POST'])
@app.route('/adhoc_server/setup_adhoc_server', methods=['PUT', 'POST'])
def setup_adhoc_server():
    """
    Set up a wireless ad-hoc (IBSS) connection with this system acting as
    the server.

    Keyword arguments:
    channel - 802.11 channel number to use when setting up the ad-hoc
              server.
    ip_address - IPv4 address to use for this server.

    Return value:
    JSON object with the SSID for the client to use in order to initiate an IBSS
    connection with this server.

    """
    # Check if there is a previous connection still active
    if system._adhoc_connection_exists():
        return write_json_error('Previous connection still exists')
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
    channel = flask.request.values.get('channel')
    ip_address = flask.request.values.get('ip_address')
    ssid = None
    connection_name = None

    output = system._run_command("hostname")
    match = re.search("(?P<host>^[^\.]+)", output)
    if match:
        hostname = match.group('host')
        ssid = 'test-ibss-' + hostname

    if ssid is None:
        return write_json_error('Unable to generate ssid for ad-hoc connection')

    # Create the ad-hoc connection in NetworkManager
    output = system._run_command(
        "nmcli con add ifname {ifname} type wifi ".format(
            ifname = system.get_available_wireless_interface_name(),
        ) + "con-name {con_name} ssid {ssid} mode adhoc".format(
            con_name = system.get_connection_name(),
            ssid = ssid,
        )
    )

    # Check for error in ad-hoc connection creation
    if system._nmcli_error_exists(output = output):
        return write_json_error('Unable to create the ad-hoc connection')

    # Get the name of the connection created
    match = re.search(
        "Connection '(?P<con_name>.+?)' .+? successfully added",
        output,
    )
    if match:
        connection_name = match.group('con_name')
        # Make sure the connection name we get back matches the connection name
        # we have dedicated for created ad-hoc connections
        if connection_name != system.get_connection_name():
            return write_json_error(
                'Unable to properly create the ad-hoc connection'
            )
    else:
        return write_json_error(
            'Unable to determine the name of the ad-hoc connection'
        )

    band = None
    # Figure out if the wireless band we're operating in is either "bg" (2.4GHz)
    # or "a" (5GHz)
    for band_name in channel_band_map.keys():
        if int(channel) >= channel_band_map[band_name]['start'] and \
            int(channel) <= channel_band_map[band_name]['end']:
            band = band_name
            break

    if not band:
        return write_json_error(
            'Channel {0} does not have an associated wireless band'.format(
                channel
            )
        )

    # Set up the channel and IP address for the connection
    output = system._run_command(
        "nmcli con modify {con_name} ".format(
            con_name = connection_name,
        ) + "802-11-wireless.channel {channel} ".format(
            channel = channel,
        ) + "802-11-wireless.band {band} ipv4.method manual ".format(
            band = band,
        ) + "ipv4.addresses {ip_address}".format(
            ip_address = ip_address,
        )
    )

    # Check for error in ad-hoc connection modification
    if system._nmcli_error_exists(output = output):
        system._run_command(
            "nmcli con delete {con_name}".format(con_name = connection_name)
        )
        return write_json_error(
            'Unable to properly configure the ad-hoc connection'
        )

    # Bring the connection up
    output = system._run_command(
        "nmcli con up {con_name}".format(con_name = connection_name)
    )

    # Check for error in bringing the ad-hoc connection up
    if system._nmcli_error_exists(output = output):
        system._run_command(
            "nmcli con delete {con_name}".format(con_name = connection_name)
        )
        return write_json_error('Unable to bring the ad-hoc connection up')

    # Verify that the connection is up according to the output
    match = re.search("Connection successfully activated", output)
    if not match:
        system._run_command(
            "nmcli con delete {con_name}".format(con_name = connection_name)
        )
        return write_json_error(
            'Unable to determine if the ad-hoc connection came up'
        )

    # Return the connection details to the orchestration server
    return flask.jsonify(
        {
            'ssid': ssid,
        }
    )

@app.route('/adhoc_server/teardown_adhoc_server/', methods=['DELETE'])
@app.route('/adhoc_server/teardown_adhoc_server', methods=['DELETE'])
def teardown_adhoc_server():
    """
    Teardown an already configured wireless ad-hoc (IBSS) connection.

    """
    if not system._adhoc_connection_exists():
        return write_json_error('Previous connection does not exist')
    # Bring down the connection
    output = system._run_command(
        "nmcli con down {con_name}".format(
            con_name = system.get_connection_name(),
        )
    )

    # Verify that the connection is down according to the output
    disconnection_pattern = \
        "Connection '{con_name}' successfully deactivated".format(
            con_name = system.get_connection_name(),
        )
    match = re.search(disconnection_pattern, output)
    if not match:
        return write_json_error('Unable to bring the ad-hoc connection down')

    # Delete the connection in NetworkManager
    output = system._run_command(
        "nmcli con delete {con_name}".format(
            con_name = system.get_connection_name()
        )
    )

    # Verify that the connection is deleted according to the output
    deletion_pattern = \
        "Connection '{con_name}' .+? successfully deleted".format(
            con_name = system.get_connection_name(),
        )
    match = re.search(deletion_pattern, output)
    if not match:
        return write_json_error('Unable to delete the ad-hoc connection')

    return flask.jsonify({})

if __name__ == '__main__':
    app.run(debug = True)
