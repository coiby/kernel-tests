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
The worknode.linux.manager.rhel7.audio module provides a class (AudioManager)
that manages all audio-related activities.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.manager.rhel7.audio
from worknode.exception.worknode_executable import *
from constants.time import *

class IntegerSoundcardControl(worknode.linux.manager.rhel7.audio.SoundcardControl):
    """
    Class representing a soundcard control that uses integer values.

    """
    def __init__(self, parent, num_id):
        super(IntegerSoundcardControl, self).__init__(
            parent = parent,
            num_id = num_id,
        )
        self._configure_executables()
        self._configure_property_manager()

    def _configure_executables(self):
        # Configure amixer parser
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_cget_object = amixer.get_amixer_command(
            command_string = 'cget',
        )
        amixer_cget_command_parser = amixer_cget_object.get_command_parser()
        amixer_cget_command_parser.set_column_titles(
            titles = [
                'interface',
                'name',
                'type',
                'access',
                'number_of_values',
                'minimum',
                'maximum',
                'step',
                'values',
            ],
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = 'min=(?P<minimum>\d+),max=(?P<maximum>\d+),step=(?P<step>\d+)',
        )

    def _configure_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'minimum')
        property_manager.initialize_property(property_name = 'maximum')
        property_manager.initialize_property(property_name = 'step')
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_cget_object = amixer.get_amixer_command(command_string = 'cget')
        amixer_cget_command = amixer_cget_object.get_command(
            command_arguments = 'numid=' + str(self.get_id()),
        )
        amixer_cget_parser = amixer_cget_object.get_command_parser()
        # Add the command managers
        amixer_cget_manager = property_manager.get_command_manager(
            manager_name = 'amixer_cget',
        )
        # Set the property mappings
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'minimum',
            internal_property_name = 'minimum',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'maximum',
            internal_property_name = 'maximum',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'step',
            internal_property_name = 'step',
        )
        # Set up the parsers
        amixer_cget_manager.set_command_parser(parser = amixer_cget_parser)
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'minimum',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'maximum',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'step',
            command_priority = ['amixer_cget'],
        )

    def get_minimum_value(self):
        """
        Get the minimum settable value of the soundcard control.

        Return value:
        Minimum settable value of the soundcard control.

        """
        return int(
            self.get_property_manager().get_property_value(
                property_name = 'minimum',
            )[0]
        )

    def get_maximum_value(self):
        """
        Get the maximum settable value of the soundcard control.

        Return value:
        Maximum settable value of the soundcard control.

        """
        return int(
            self.get_property_manager().get_property_value(
                property_name = 'maximum',
            )[0]
        )

    def get_step_value(self):
        """
        Get the incremental raw step value of the soundcard control.

        Return value:
        Incremental raw step value of the soundcard control.

        """
        return int(
            self.get_property_manager().get_property_value(
                property_name = 'step',
            )[0]
        )

class MixerIntegerSoundcardControl(IntegerSoundcardControl):
    """
    Class representing a mixer interface integer control (typically volume
    control).

    """
    def _configure_executables(self):
        # Configure amixer parser
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_cget_object = amixer.get_amixer_command(
            command_string = 'cget',
        )
        amixer_cget_command_parser = amixer_cget_object.get_command_parser()
        amixer_cget_command_parser.set_column_titles(
            titles = [
                'interface',
                'name',
                'type',
                'access',
                'number_of_values',
                'minimum',
                'maximum',
                'step',
                'values',
                'dbscale_minimum',
                'dbscale_step',
                'mute',
            ],
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = 'min=(?P<minimum>\d+),max=(?P<maximum>\d+),step=(?P<step>\d+)',
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = 'dBscale-min=(?P<dbscale_minimum>-?\d+\.?\d*dB),step=(?P<dbscale_step>\d+\.?\d*dB),mute=(?P<mute>\d+)',
        )

    def _configure_property_manager(self):
        super(MixerIntegerSoundcardControl, self)._configure_property_manager()
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'dbscale_minimum')
        property_manager.initialize_property(property_name = 'dbscale_step')
        property_manager.initialize_property(property_name = 'mute')
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_cget_object = amixer.get_amixer_command(command_string = 'cget')
        amixer_cget_command = amixer_cget_object.get_command(
            command_arguments = 'numid=' + str(self.get_id()),
        )
        amixer_cget_parser = amixer_cget_object.get_command_parser()
        # Add the command managers
        amixer_cget_manager = property_manager.get_command_manager(
            manager_name = 'amixer_cget',
        )
        # Set the property mappings
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'dbscale_minimum',
            internal_property_name = 'dbscale_minimum',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'dbscale_step',
            internal_property_name = 'dbscale_step',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'mute',
            internal_property_name = 'mute',
        )
        # Set up the parsers
        amixer_cget_manager.set_command_parser(parser = amixer_cget_parser)
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'dbscale_minimum',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'dbscale_step',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'mute',
            command_priority = ['amixer_cget'],
        )

    def get_dbscale_minimum_value(self):
        """
        Get the minimum settable decibel (dB) value of the soundcard control.

        Return value:
        Minimum settable decibel (dB) value of the soundcard control.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'dbscale_minimum',
        )[0]

    def get_dbscale_step_value(self):
        """
        Get the incremental decibel (dB) step value of the soundcard control.

        Return value:
        Incremental decibel (dB) step value of the soundcard control.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'dbscale_step',
        )[0]

    def get_mute_value(self):
        """
        Get the mute value of the soundcard control.

        Return value:
        Mute value of the soundcard control.

        """
        return self.get_property_manager().get_property_value(
            property_name = 'mute',
        )[0]

    def set_volume_percentage(self, percent, preferred_command = 'amixer'):
        """
        Set the volume on the control based on a percentage (0-100).

        Keyword arguments:
        percent - Integer from 0 to 100 (inclusive).
        preferred_command - Command to use when performing the action.

        """
        percent = int(percent)
        if percent < 0 or percent > 100:
            raise Exception("percent argument needs to be between 0-100")
        self.set_raw_value(
            value = str(percent) + '%',
            preferred_command = preferred_command,
        )

    def set_volume_value(self, value, preferred_command = 'amixer'):
        """
        Set the volume on the control based on its range of acceptable raw
        values.

        Keyword arguments:
        value - Integer between the minimum and maximum value (inclusive).
        preferred_command - Command to use when performing the action.

        """
        value = int(value)
        minimum = self.get_minimum_value()
        maximum = self.get_maximum_value()
        if value < minimum or value > maximum:
            raise Exception(
                "value argument needs to be between {0}-{1}".format(
                    minimum,
                    maximum,
                )
            )
        self.set_raw_value(
            value = str(value),
            preferred_command = preferred_command,
        )

    def get_volume_value(self):
        """
        Get the current volume on the control.

        """
        values = self.get_values()
        return int(values[0])

class PCMIntegerSoundcardControl(IntegerSoundcardControl):
    """
    Class representing a PCM interface integer control (typically channel
    mapping).

    """
    def _configure_executables(self):
        # Configure amixer parser
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_cget_object = amixer.get_amixer_command(
            command_string = 'cget',
        )
        amixer_cget_command_parser = amixer_cget_object.get_command_parser()
        amixer_cget_command_parser.set_column_titles(
            titles = [
                'interface',
                'name',
                'device_number',
                'type',
                'access',
                'number_of_values',
                'minimum',
                'maximum',
                'step',
                'values',
                'channel_maps',
            ],
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = 'numid=\d+,iface=(?P<interface>\w+),name=\'(?P<name>.*?)\',device=(?P<device_number>\d+)',
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = 'min=(?P<minimum>\d+),max=(?P<maximum>\d+),step=(?P<step>\d+)',
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = '\|\s+chmap-(?P<channel_maps>\w+=\S+)',
        )

    def _configure_property_manager(self):
        super(PCMIntegerSoundcardControl, self)._configure_property_manager()
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'device_number')
        property_manager.initialize_property(property_name = 'channel_maps')
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_cget_object = amixer.get_amixer_command(command_string = 'cget')
        amixer_cget_command = amixer_cget_object.get_command(
            command_arguments = 'numid=' + str(self.get_id()),
        )
        amixer_cget_parser = amixer_cget_object.get_command_parser()
        # Add the command managers
        amixer_cget_manager = property_manager.get_command_manager(
            manager_name = 'amixer_cget',
        )
        # Set the property mappings
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'device_number',
            internal_property_name = 'device_number',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'channel_maps',
            internal_property_name = 'channel_maps',
        )
        # Set up the parsers
        amixer_cget_manager.set_command_parser(parser = amixer_cget_parser)
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'device_number',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'channel_maps',
            command_priority = ['amixer_cget'],
        )

    def get_device_number(self):
        """
        Get the device number of the soundcard control.

        Return value:
        Device number of the control.

        """
        device_number = 0
        try:
            device_number = self.get_property_manager().get_property_value(
                property_name = 'device_number',
            )[0]
        except TypeError:
            device_number = 0
        return int(device_number)

    def get_channel_mappings(self):
        """
        Get a list of the possible enumerated values of the soundcard control.

        Return value:
        List of the possible enumerated values of the soundcard control.

        """
        class ChannelMap(object):
            """
            Object that represents an individual channel map. Also will note if
            the channel map is fixed or variable.

            """
            def __init__(self, map_string, type_string):
                """
                Keyword argument:
                map_string - String representing the channel arrangement.
                type_string - String noting if the map is fixed or variable.

                """
                self.map_string = map_string
                self.fixed = False
                if type_string == 'fixed':
                    self.fixed = True

            def get_map(self):
                """
                Get the map of the channels as a list of the channels in their
                order.

                Return values:
                List of channels in their order.

                """
                return self.map_string.split(',')

            def is_fixed(self):
                """
                Get if the channel map is fixed or not.

                Return values:
                True if the channel map is fixed. False if the channel map is
                variable.

                """
                return self.fixed

            def is_variable(self):
                """
                Get if the channel map is variable or not.

                Return values:
                True if the channel map is variable. False if the channel map is
                fixed.

                """
                return not self.fixed

        channel_maps_list = self.get_property_manager().get_property_value(
            property_name = 'channel_maps',
        )
        channel_maps = []
        for channel_map in channel_maps_list:
            match = re.search('(?P<type>\w+)=(?P<map>\S+)', channel_map)
            if match:
                map_object = ChannelMap(
                    map_string = match.group('map'),
                    type_string = match.group('type'),
                )
                channel_maps.append(map_object)
        return channel_maps

class BooleanSoundcardControl(worknode.linux.manager.rhel7.audio.SoundcardControl):
    """
    Class representing a soundcard control that uses boolean (on/off) values.

    """
    def __init__(self, parent, num_id):
        super(BooleanSoundcardControl, self).__init__(
            parent = parent,
            num_id = num_id,
        )

    def is_on(self):
        """
        Check if the soundcard control is on.

        Return value:
        True if the soundcard control is on. False if the soundcard control is
        off.

        """
        is_on = True
        for value in self.get_values():
            if value == 'off':
                is_on = False
                break
        return is_on

    def is_off(self):
        """
        Check if the soundcard control is off.

        Return value:
        True if the soundcard control is off. False if the soundcard control is
        on.

        """
        is_off = True
        for value in self.get_values():
            if value == 'on':
                is_off = False
                break
        return is_off

    def set_on(self, preferred_command = 'amixer'):
        """
        Set the soundcard control to on.

        Keyword arguments:
        preferred_command - Command to use when performing the action.

        """
        self.set_raw_value(
            value = 'on',
            preferred_command = preferred_command,
        )

    def set_off(self, preferred_command = 'amixer'):
        """
        Set the soundcard control to off.

        Keyword arguments:
        preferred_command - Command to use when performing the action.

        """
        self.set_raw_value(
            value = 'off',
            preferred_command = preferred_command,
        )

class EnumeratedSoundcardControl(worknode.linux.manager.rhel7.audio.SoundcardControl):
    """
    Class representing a soundcard control that uses integer values.

    """
    def __init__(self, parent, num_id):
        super(EnumeratedSoundcardControl, self).__init__(
            parent = parent,
            num_id = num_id,
        )
        self.__configure_executables()
        self.__configure_property_manager()

    def __configure_executables(self):
        # Configure amixer parser
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_cget_object = amixer.get_amixer_command(
            command_string = 'cget',
        )
        amixer_cget_command_parser = amixer_cget_object.get_command_parser()
        amixer_cget_command_parser.set_column_titles(
            titles = [
                'interface',
                'name',
                'type',
                'access',
                'number_of_values',
                'number_of_items',
                'items',
                'values',
            ],
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = 'items=(?P<number_of_items>\d+)',
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = '; Item #(?P<items>\d+ .*)',
        )

    def __configure_property_manager(self):
        property_manager = self.get_property_manager()
        property_manager.initialize_property(property_name = 'number_of_items')
        property_manager.initialize_property(property_name = 'items')
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_cget_object = amixer.get_amixer_command(command_string = 'cget')
        amixer_cget_command = amixer_cget_object.get_command(
            command_arguments = 'numid=' + str(self.get_id()),
        )
        amixer_cget_parser = amixer_cget_object.get_command_parser()
        # Add the command managers
        amixer_cget_manager = property_manager.get_command_manager(
            manager_name = 'amixer_cget',
        )
        # Set the property mappings
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'number_of_items',
            internal_property_name = 'number_of_items',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'items',
            internal_property_name = 'items',
        )
        # Set up the parsers
        amixer_cget_manager.set_command_parser(parser = amixer_cget_parser)
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'number_of_items',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'items',
            command_priority = ['amixer_cget'],
        )

    def get_number_of_enumerated_values(self):
        """
        Get the number of enumerated values of the soundcard control.

        Return value:
        Number of enumerated values of the soundcard control.

        """
        return int(
            self.get_property_manager().get_property_value(
                property_name = 'number_of_items',
            )[0]
        )

    def get_enumerated_values(self):
        """
        Get a list of the possible enumerated values of the soundcard control.

        Return value:
        List of the possible enumerated values of the soundcard control.

        """
        items = self.get_property_manager().get_property_value(
            property_name = 'items',
        )
        number_of_values = self.get_number_of_enumerated_values()
        enumerated_values = []
        for index in range(0, number_of_values):
            enumerated_values.append(None)
        for item in items:
            match = re.search('(?P<index>\d+) \'(?P<value>.*?)\'', item)
            if match:
                enumerated_values[int(match.group('index'))] = match.group('value')
        return enumerated_values

    def get_enumerated_value(self):
        """
        Get the current enumerated value of the soundcard control.

        Return value:
        Current enumerated value of the soundcard control.

        """
        enumerated_values = self.get_enumerated_values()
        index = int(self.get_values()[0])
        return enumerated_values[index]


    def set_enumerated_value(self, value, preferred_command = 'amixer'):
        """
        Set the enumerated value of the soundcard control.

        Keyword arguments:
        value - One of the available enumerated values.
        preferred_command - Command to use when performing the action.

        """
        enumerated_values = self.get_enumerated_values()
        if value not in enumerated_values:
            raise Exception(
                "value argument is not one of the available enumerated values"
            )
        self.set_raw_value(
            value = enumerated_values.index(value),
            preferred_command = preferred_command,
        )

class BytesSoundcardControl(worknode.linux.manager.rhel7.audio.SoundcardControl):
    """
    Class representing a soundcard control that uses byte values.

    """
    def __init__(self, parent, num_id):
        super(BytesSoundcardControl, self).__init__(
            parent = parent,
            num_id = num_id,
        )

class IEC958SoundcardControl(worknode.linux.manager.rhel7.audio.SoundcardControl):
    """
    Class representing a soundcard control that uses IEC958 (S/PDIF) values.

    """
    def __init__(self, parent, num_id):
        super(IEC958SoundcardControl, self).__init__(
            parent = parent,
            num_id = num_id,
        )
