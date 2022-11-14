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

import worknode.linux.manager.audio_base
import worknode.linux.util.amixer
from worknode.exception.worknode_executable import *
from constants.time import *

class AudioManager(worknode.linux.manager.audio_base.AudioManager):
    """
    AudioManager is an object that manages all audio-related activities. It
    acts as a container for audio-related commands as well as being a unified
    place to request abstracted audio information from and control the sound
    card audio from.

    """
    def __init__(self, parent):
        super(AudioManager, self).__init__(parent = parent)
        self.__configure_property_manager()

    def __configure_property_manager(self):
        property_manager = self.get_property_manager()
        # Configure sysfs command manager
        sysfs_command = 'ls -1 /sys/class/sound/'
        lspci_command = 'lspci -n | grep " 0403: "'
        # Add the command managers
        sysfs_command_manager = property_manager.add_command_manager(
            manager_name = 'sysfs',
            command = sysfs_command,
        )
        lspci_command_manager = property_manager.add_command_manager(
            manager_name = 'lspci',
            command = lspci_command,
        )
        # Set the property mappings
        sysfs_command_manager.set_property_mapping(
            command_property_name = 'soundcard_index',
            internal_property_name = 'soundcard_index',
        )
        lspci_command_manager.set_property_mapping(
            command_property_name = 'soundcard_pciid',
            internal_property_name = 'soundcard_pciid',
        )
        # Set up the parsers
        sysfs_parser = sysfs_command_manager.initialize_command_parser(
            parser_type = 'table',
        )
        sysfs_parser.set_column_titles(titles = ['soundcard_index'])
        sysfs_parser.add_regular_expression(
            regex = 'card(?P<soundcard_index>\d+)',
        )
        lspci_parser = lspci_command_manager.initialize_command_parser(
            parser_type = 'table',
        )
        lspci_parser.set_column_titles(titles = ['soundcard_pciid'])
        lspci_parser.add_regular_expression(
            regex = '[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f] [0-9a-f]{4}: '
                + '(?P<soundcard_pciid>[0-9a-f]{4}:[0-9a-f]{4})',
        )
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'soundcard_index',
            command_priority = ['sysfs'],
        )
        property_manager.set_command_priority(
            property_name = 'soundcard_pciid',
            command_priority = ['lspci'],
        )

    def _create_soundcard(self, index):
        soundcard = Soundcard(
            parent = self,
            index = index,
        )
        self._add_soundcard(soundcard_object = soundcard)

class Soundcard(worknode.linux.manager.audio_base.Soundcard):
    """
    Base class for different types of soundcards to inherit from.

    """
    def __init__(self, parent, index):
        super(Soundcard, self).__init__(parent = parent, index = index)
        self.__configure_executables()
        self.__configure_property_manager()
        self._set_soundcard_control_factory(
            factory_object = SoundcardControlFactory(),
        )

    def __configure_executables(self):
        # Configure amixer
        amixer = self.add_command(
            command_name = 'amixer',
            command_object = worknode.linux.util.amixer.amixer(
                work_node = self._get_work_node(),
            ),
        )
        # Add amixer controls command.
        amixer_controls_command = amixer.add_amixer_command(
            command_string = 'controls',
        )
        amixer_controls_command.add_option(
            option_flag = '-c',
            option_value = str(self.get_index()),
        )
        amixer_controls_command_parser = amixer_controls_command.initialize_command_parser(
            output_type = 'table',
        )
        amixer_controls_command_parser.set_column_titles(titles = ['id'])
        amixer_controls_command_parser.add_regular_expression(
            regex = 'numid=(?P<id>\d+),iface=\w+,name=\'.*?\'',
        )
        # Add amixer info command.
        amixer_info_command = amixer.add_amixer_command(command_string = 'info')
        amixer_info_command.add_option(
            option_flag = '-c',
            option_value = str(self.get_index()),
        )
        amixer_info_command_parser = amixer_info_command.initialize_command_parser(
            output_type = 'table',
        )
        amixer_info_command_parser.set_column_titles(
            titles = [
                'card_type',
                'card_name',
                'mixer_name',
                'components',
                'number_of_controls',
                'number_of_simple_controls',
            ],
        )
        amixer_info_command_parser.add_regular_expression(
            regex = "Card hw:\d+ '(?P<card_type>.+)'/'(?P<card_name>.+) at",
        )
        amixer_info_command_parser.add_regular_expression(
            regex = "Mixer name\s+: '(?P<mixer_name>.+)'",
        )
        amixer_info_command_parser.add_regular_expression(
            regex = "Components\s+: '(?P<components>.+)'",
        )
        amixer_info_command_parser.add_regular_expression(
            regex = "Controls\s+: (?P<number_of_controls>\d+)",
        )
        amixer_info_command_parser.add_regular_expression(
            regex = "Simple ctrls\s+: (?P<number_of_simple_controls>\d+)",
        )

    def __configure_property_manager(self):
        property_manager = self.get_property_manager()
        # Configure amixer command manager
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_controls_command_object = amixer.get_amixer_command(
            command_string = 'controls',
        )
        amixer_controls_command = amixer_controls_command_object.get_command()
        amixer_controls_parser = amixer_controls_command_object.get_command_parser()
        amixer_info_command_object = amixer.get_amixer_command(
            command_string = 'info',
        )
        amixer_info_command = amixer_info_command_object.get_command()
        amixer_info_parser = amixer_info_command_object.get_command_parser()
        # Add the command managers
        amixer_controls_manager = property_manager.add_command_manager(
            manager_name = 'amixer_controls',
            command = amixer_controls_command,
        )
        amixer_info_manager = property_manager.add_command_manager(
            manager_name = 'amixer_info',
            command = amixer_info_command,
        )
        procfs_id_manager = property_manager.add_command_manager(
            manager_name = 'procfs_id',
            command = 'cat /proc/asound/card{0}/id'.format(self.get_index()),
        )
        sys_vendor_command_manager = property_manager.add_command_manager(
            manager_name = 'sys_vendor',
            command = 'cat /sys/class/sound/card{0}/device/vendor'.format(
                self.get_index()
            )
        )
        sys_device_command_manager = property_manager.add_command_manager(
            manager_name = 'sys_device',
            command = 'cat /sys/class/sound/card{0}/device/device'.format(
                self.get_index()
            )
        )
        sys_subsystem_vendor_command_manager = property_manager.add_command_manager(
            manager_name = 'sys_subsystem_vendor',
            command = 'cat /sys/class/sound/card{0}/device/subsystem_vendor'.format(
                self.get_index()
            )
        )
        sys_subsystem_device_command_manager = property_manager.add_command_manager(
            manager_name = 'sys_subsystem_device',
            command = 'cat /sys/class/sound/card{0}/device/subsystem_device'.format(
                self.get_index()
            )
        )
        # Set the property mappings
        amixer_controls_manager.set_property_mapping(
            command_property_name = 'id',
            internal_property_name = 'id',
        )
        procfs_id_manager.set_property_mapping(
            command_property_name = 'name',
            internal_property_name = 'name',
        )
        sys_vendor_command_manager.set_property_mapping(
            command_property_name = 'vendor_id',
            internal_property_name = 'vendor_id',
        )
        sys_device_command_manager.set_property_mapping(
            command_property_name = 'device_id',
            internal_property_name = 'device_id',
        )
        sys_subsystem_vendor_command_manager.set_property_mapping(
            command_property_name = 'subsystem_vendor_id',
            internal_property_name = 'subsystem_vendor_id',
        )
        sys_subsystem_device_command_manager.set_property_mapping(
            command_property_name = 'subsystem_device_id',
            internal_property_name = 'subsystem_device_id',
        )
        amixer_info_manager.set_property_mapping(
            command_property_name = 'card_type',
            internal_property_name = 'card_type',
        )
        amixer_info_manager.set_property_mapping(
            command_property_name = 'card_name',
            internal_property_name = 'card_name',
        )
        amixer_info_manager.set_property_mapping(
            command_property_name = 'mixer_name',
            internal_property_name = 'mixer_name',
        )
        amixer_info_manager.set_property_mapping(
            command_property_name = 'components',
            internal_property_name = 'components',
        )
        amixer_info_manager.set_property_mapping(
            command_property_name = 'number_of_controls',
            internal_property_name = 'number_of_controls',
        )
        amixer_info_manager.set_property_mapping(
            command_property_name = 'number_of_simple_controls',
            internal_property_name = 'number_of_simple_controls',
        )
        # Set up the parsers
        amixer_controls_manager.set_command_parser(
            parser = amixer_controls_parser,
        )
        procfs_id_parser = procfs_id_manager.initialize_command_parser(
            parser_type = 'single',
        )
        procfs_id_parser.set_export_key(key = 'name')
        procfs_id_parser.set_regex(regex = '(\w+)')
        sys_vendor_parser = sys_vendor_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        sys_vendor_parser.set_export_key(key = 'vendor_id')
        sys_vendor_parser.set_regex(regex = '(0x\w+)')
        sys_device_parser = sys_device_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        sys_device_parser.set_export_key(key = 'device_id')
        sys_device_parser.set_regex(regex = '(0x\w+)')
        sys_subsystem_vendor_parser = sys_subsystem_vendor_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        sys_subsystem_vendor_parser.set_export_key(key = 'subsystem_vendor_id')
        sys_subsystem_vendor_parser.set_regex(regex = '(0x\w+)')
        sys_subsystem_device_parser = sys_subsystem_device_command_manager.initialize_command_parser(
            parser_type = 'single',
        )
        sys_subsystem_device_parser.set_export_key(key = 'subsystem_device_id')
        sys_subsystem_device_parser.set_regex(regex = '(0x\w+)')
        amixer_info_manager.set_command_parser(
            parser = amixer_info_parser,
        )
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'id',
            command_priority = ['amixer_controls'],
        )
        property_manager.set_command_priority(
            property_name = 'name',
            command_priority = ['procfs_id'],
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
            property_name = 'subsystem_vendor_id',
            command_priority = ['sys_subsystem_vendor'],
        )
        property_manager.set_command_priority(
            property_name = 'subsystem_device_id',
            command_priority = ['sys_subsystem_device'],
        )
        property_manager.set_command_priority(
            property_name = 'card_type',
            command_priority = ['amixer_info'],
        )
        property_manager.set_command_priority(
            property_name = 'card_name',
            command_priority = ['amixer_info'],
        )
        property_manager.set_command_priority(
            property_name = 'mixer_name',
            command_priority = ['amixer_info'],
        )
        property_manager.set_command_priority(
            property_name = 'components',
            command_priority = ['amixer_info'],
        )
        property_manager.set_command_priority(
            property_name = 'number_of_controls',
            command_priority = ['amixer_info'],
        )
        property_manager.set_command_priority(
            property_name = 'number_of_simple_controls',
            command_priority = ['amixer_info'],
        )

class SoundcardControlFactory(worknode.linux.manager.audio_base.SoundcardControlFactory):
    """
    Factory class for generating SoundcardControl objects specific to the value
    types of the soundcard control.

    """
    def get_soundcard_control(self, parent, num_id):
        """
        Generate subclassed SoundcardControl object given the num_id of the
        control.

        """
        import worknode.linux.manager.rhel7.soundcard.control
        control = None
        base_control = SoundcardControl(
            parent = parent,
            num_id = num_id,
        )
        control_type = base_control.get_type()
        interface = base_control.get_interface()
        del base_control
        if control_type == 'INTEGER' and interface == 'MIXER':
            control = worknode.linux.manager.rhel7.soundcard.control.MixerIntegerSoundcardControl(
                parent = parent,
                num_id = num_id,
            )
        elif control_type == 'INTEGER' and interface == 'PCM':
            control = worknode.linux.manager.rhel7.soundcard.control.PCMIntegerSoundcardControl(
                parent = parent,
                num_id = num_id,
            )
        elif control_type == 'BOOLEAN':
            control = worknode.linux.manager.rhel7.soundcard.control.BooleanSoundcardControl(
                parent = parent,
                num_id = num_id,
            )
        elif control_type == 'ENUMERATED':
            control = worknode.linux.manager.rhel7.soundcard.control.EnumeratedSoundcardControl(
                parent = parent,
                num_id = num_id,
            )
        elif control_type == 'BYTES':
            control = worknode.linux.manager.rhel7.soundcard.control.BytesSoundcardControl(
                parent = parent,
                num_id = num_id,
            )
        elif control_type == 'IEC958':
            control = worknode.linux.manager.rhel7.soundcard.control.IEC958SoundcardControl(
                parent = parent,
                num_id = num_id,
            )
        else:
            raise Exception(
                "Unknown soundcard control type: {0}".format(control_type)
            )
        return control

class SoundcardControl(worknode.linux.manager.audio_base.SoundcardControl):
    """
    Class representing different types of soundcard controls.

    """
    def __init__(self, parent, num_id):
        super(SoundcardControl, self).__init__(parent = parent, num_id = num_id)
        self.__configure_executables()
        self.__configure_property_manager()

    def __configure_executables(self):
        # Configure amixer
        amixer = self.add_command(
            command_name = 'amixer',
            command_object = worknode.linux.util.amixer.amixer(
                work_node = self._get_work_node(),
            ),
        )
        # Add amixer cget command.
        amixer_cget_command = amixer.add_amixer_command(command_string = 'cget')
        amixer_cget_command.add_option(
            option_flag = '-c',
            option_value = str(self._get_soundcard().get_index()),
        )
        amixer_cget_command_parser = amixer_cget_command.initialize_command_parser(
            output_type = 'table',
        )
        amixer_cget_command_parser.set_column_titles(
            titles = [
                'interface',
                'name',
                'type',
                'access',
                'number_of_values',
                'values',
            ],
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = 'numid=\d+,iface=(?P<interface>\w+),name=\'(?P<name>.*?)\'',
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = '; type=(?P<type>\w+),access=(?P<access>.*?),values=(?P<number_of_values>\d+)',
        )
        amixer_cget_command_parser.add_regular_expression(
            regex = ': values=(?P<values>.*)',
        )
        # Add amixer cset command.
        amixer_cset_command = amixer.add_amixer_command(command_string = 'cset')
        amixer_cset_command.add_option(
            option_flag = '-c',
            option_value = str(self._get_soundcard().get_index()),
        )

    def __configure_property_manager(self):
        property_manager = self.get_property_manager()
        # Configure amixer command manager
        amixer = self.get_command_object(command_name = 'amixer')
        amixer_cget_object = amixer.get_amixer_command(command_string = 'cget')
        amixer_cget_command = amixer_cget_object.get_command(
            command_arguments = 'numid=' + str(self.get_id()),
        )
        amixer_cget_parser = amixer_cget_object.get_command_parser()
        # Add the command managers
        amixer_cget_manager = property_manager.add_command_manager(
            manager_name = 'amixer_cget',
            command = amixer_cget_command,
        )
        # Set the property mappings
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'interface',
            internal_property_name = 'interface',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'name',
            internal_property_name = 'name',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'type',
            internal_property_name = 'type',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'access',
            internal_property_name = 'access',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'number_of_values',
            internal_property_name = 'number_of_values',
        )
        amixer_cget_manager.set_property_mapping(
            command_property_name = 'values',
            internal_property_name = 'values',
        )
        # Set up the parsers
        amixer_cget_manager.set_command_parser(parser = amixer_cget_parser)
        # Set the command priorities
        property_manager.set_command_priority(
            property_name = 'interface',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'name',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'type',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'access',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'number_of_values',
            command_priority = ['amixer_cget'],
        )
        property_manager.set_command_priority(
            property_name = 'values',
            command_priority = ['amixer_cget'],
        )

    def get_values(self):
        """
        Get the value(s) of the soundcard control.

        Return value:
        List of value(s) of the soundcard control.

        """
        values = super(SoundcardControl, self).get_values().split(',')
        return values

    def is_read_only(self):
        """
        Check if the soundcard control is read only.

        Return value:
        True if the soundcard control is read only, False otherwise.

        """
        read_only = False
        access = self.get_access()
        if re.search('^r-', access):
            read_only = True
        return read_only

    def set_raw_value(self, value, preferred_command = 'amixer'):
        """
        Set the raw value of the soundcard control.

        Keyword arguments:
        value - Value to set the control to.
        preferred_command - Command to use when performing the action.

        """
        if self.is_read_only():
            raise Exception("Control cannot have value set as it is read only")

        if preferred_command == 'amixer':
            amixer = self.get_command_object(command_name = 'amixer')
            amixer_cset_object = amixer.get_amixer_command(
                command_string = 'cset',
            )
            amixer_cset_object.run_command(
                command_arguments = 'numid={num_id} {value}'.format(
                    num_id = self.get_id(),
                    value = value,
                ),
            )
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )
        self.get_property_manager().refresh_properties()
