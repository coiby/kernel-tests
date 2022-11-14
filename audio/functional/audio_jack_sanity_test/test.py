#!/usr/bin/python
# Copyright (c) 2015 Red Hat, Inc. All rights reserved. This copyrighted material
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
# Maintainer: Erik Hamera

"""
The functional.audio_jack_sanity_test.test module provides a class (Test)
that checks to make sure that the detected soundcards in the system show all the
expected audio jacks.

"""

__author__ = 'Erik Hamera'

import json

import base.test
import worknode.worknode_factory
from base.exception.test import *
from worknode.linux.manager.exception.file_system import *

class Test(base.test.Test):
    """
    Test performs a check to make sure that all the detected soundcards in the
    system show all the expected audio jacks.

    """
    def __init__(self):
        super(Test, self).__init__()
        # Set up the test information
        self.set_test_name(
            name = '/kernel/audio_tests/functional/audio_jack_sanity_test',
        )
        self.set_test_author(name = 'Erik Hamera', email = 'ehamera@redhat.com')
        self.set_test_description(
            description = 'Test that checks if the soundcards detected show '
                + 'all of the expected audio jacks.',
        )
        # Set up test variables
        self.jack_definitions_file = 'jack_definitions.json'
        self.jack_definitions = {}
        self.work_node = None
        self.__configure_test_command_line_options()
        self.__configure_test_steps()

    def __configure_test_command_line_options(self):
        self.add_command_line_option(
            '--skip_unsupported',
            dest = 'skip_unsupported',
            action = 'store_true',
            default = False,
            help = 'skip past unsupported soundcard detection',
        )

    def __configure_test_steps(self):
        self.add_test_step(
            test_step = self.read_jack_definition_file,
            test_step_description = 'Read in the audio jack definition file',
        )
        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.check_for_unsupported_soundcards,
            test_step_description = 'Check for any unsupported soundcards '
                + 'present on the work node',
        )
        self.add_test_step(
            test_step = self.check_audio_jacks,
            test_step_description = 'Check that only expected audio jack names '
                + 'are present',
        )

    def get_work_node(self):
        """
        Generate a work node object to use for the test.

        """
        self.work_node = worknode.worknode_factory.WorkNodeFactory().get_work_node()

    def read_jack_definition_file(self):
        """
        Read in the jack definition file so we know which audio jacks to expect
        on a specific soundcard.

        """
        jack_definitions_file = open(self.jack_definitions_file)
        self.jack_definitions = json.load(jack_definitions_file)
        jack_definitions_file.close()

    def check_for_unsupported_soundcards(self):
        """
        Check to see if there are any soundcards present on the work node that
        are not supported by the OS.

        """
        skip_unsupported_argument = self.get_command_line_option_value(
            dest = 'skip_unsupported',
        )
        if not skip_unsupported_argument:
            audio_manager = self.work_node.get_audio_component_manager()
            ids = audio_manager.get_unsupported_soundcard_ids()
            if ids != []:
                raise TestFailure(
                    "Found some unsupported soundcards present: {0}".format(
                        ', '.join(ids),
                    )
                )

    def check_audio_jacks(self):
        """
        Check to make sure only the expected audio jacks are present on the
        detected soundcards.

        """
        audio_manager = self.work_node.get_audio_component_manager()
        soundcards = audio_manager.get_soundcards()
        for soundcard in soundcards:
            vendor_id = soundcard.get_vendor_id()
            device_id = soundcard.get_device_id()
            subsystem_vendor_id = soundcard.get_subsystem_vendor_id()
            subsystem_device_id = soundcard.get_subsystem_device_id()
            expected_jack_names = self.get_jack_definitions(
                vendor_id = vendor_id,
                device_id = device_id,
                subsystem_vendor_id = subsystem_vendor_id,
                subsystem_device_id = subsystem_device_id,
            )
            self.get_logger().info(
                "Expecting the following jack controls for card{0}: {1}".format(
                    soundcard.get_index(),
                    ", ".join(expected_jack_names),
                )
            )
            all_controls = soundcard.get_controls()
            jack_control_names = []
            for control in all_controls:
                if control.get_interface() == 'CARD':
                    jack_control_names.append(control.get_name())
            self.get_logger().info(
                "Found the following jack controls for card{0}: {1}".format(
                    soundcard.get_index(),
                    ", ".join(jack_control_names),
                )
            )
            name_differences = list(set(expected_jack_names) - set(jack_control_names))
            if name_differences != []:
                raise TestFailure(
                    "Found a mismatch in jack names. The following names have "
                    + "no matches: {0}".format(
                        ', '.join(name_differences),
                    )
                )

    def get_jack_definitions(self, vendor_id, device_id, subsystem_vendor_id = None, subsystem_device_id = None):
        """
        Get the jack definitions for a specific soundcard.

        Keyword arguments:
        vendor_id - String of a hexidecimal ID for the vendor of the soundcard.
        device_id - String of a hexidecimal ID for the device of the soundcard.
        subsystem_vendor_id - String of a hexidecimal ID for the subsystem
                              vendor of the soundcard.
        subsystem_device_id - String of a hexidecimal ID for the subsystem
                              device of the soundcard.

        Return value:
        List of strings of the audio jack names.

        """
        jack_definitions = None
        if not vendor_id in self.jack_definitions:
            raise TestFailure(
                "Unable to find a jack definition for soundcard "
                + "{vendor_id}:{device_id}".format(
                    vendor_id = vendor_id,
                    device_id = device_id,
                )
            )
        device_dictionary = self.jack_definitions[vendor_id]
        if not device_id in device_dictionary:
            raise TestFailure(
                "Unable to find a jack definition for soundcard "
                + "{vendor_id}:{device_id}".format(
                    vendor_id = vendor_id,
                    device_id = device_id,
                )
            )
        if 'jack_definitions' in device_dictionary[device_id]:
            jack_definitions = device_dictionary[device_id]['jack_definitions']
        if 'subsystem' in device_dictionary[device_id]:
            if subsystem_vendor_id in device_dictionary[device_id]['subsystem']:
                subsystem_device_dictionary = device_dictionary[device_id]['subsystem'][subsystem_vendor_id]
                if subsystem_device_id in subsystem_device_dictionary:
                    if 'jack_definitions' in subsystem_device_dictionary[subsystem_device_id]:
                        jack_definitions = subsystem_device_dictionary[subsystem_device_id]['jack_definitions']
        if jack_definitions is None:
            raise TestFailure(
                "Uanble to find a jack definition for soundcard "
                + "{vendor_id}:{device_id}".format(
                    vendor_id = vendor_id,
                    device_id = device_id,
                )
                + ", subsystem {subsystem_vendor_id}:{subsystem_device_id}".format(
                    subsystem_vendor_id = subsystem_vendor_id,
                    subsystem_device_id = subsystem_device_id,
                )
            )
        return jack_definitions

if __name__ == '__main__':
    exit(Test().run_test())
