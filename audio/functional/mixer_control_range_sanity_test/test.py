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
The functional.mixer_control_range_sanity_test.test module provides a class
(Test) that runs through each mixer control and tests the full range of values
for that control (also testing values outside of the range).

"""

__author__ = 'Erik Hamera'

import base.test
import worknode.worknode_factory
from base.exception.test import *
from worknode.linux.manager.exception.file_system import *

class Test(base.test.Test):
    """
    Test that runs through each mixer control and tests the full range of values
    for that control (also testing values outside of the range).

    """
    def __init__(self):
        super(Test, self).__init__()
        # Set up the test information
        self.set_test_name(
            name = '/kernel/audio_tests/functional/mixer_control_range_sanity_test',
        )
        self.set_test_author(name = 'Erik Hamera', email = 'ehamera@redhat.com')
        self.set_test_description(
            description = 'Test that runs through each mixer control and tests '
                + 'the full range of values for that control (also testing '
                + 'values outside of the range).',
        )
        # Set up test variables
        self.work_node = None
        self.__configure_test_command_line_options()
        self.__configure_test_steps()

    def __configure_test_command_line_options(self):
        pass

    def __configure_test_steps(self):
        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.check_valid_mixer_ranges,
            test_step_description = 'Check each mixer control and test the '
                + 'full range of valid values for that control',
        )
        self.add_test_step(
            test_step = self.check_invalid_mixer_ranges,
            test_step_description = 'Check each mixer control and test invalid '
                + 'values for that control',
        )
        self.add_test_step(
            test_step = self.check_setting_same_mixer_value,
            test_step_description = 'Check each mixer control and attempt to '
                + 'set its value to the same value it is currently set at',
        )

    def get_work_node(self):
        """
        Generate a work node object to use for the test.

        """
        self.work_node = worknode.worknode_factory.WorkNodeFactory().get_work_node()

    def check_valid_mixer_ranges(self):
        """
        Check to make sure that all valid values for a mixer control can be set.

        """
        audio_manager = self.work_node.get_audio_component_manager()
        soundcards = audio_manager.get_soundcards()
        if soundcards == []:
            raise TestFailure("Unable to find any soundcards on the work node")
        for soundcard in soundcards:
            controls = soundcard.get_controls()
            mixer_controls = []
            for control in controls:
                if control.get_interface() == 'MIXER' and not control.is_read_only():
                    self.__check_valid_control_range(control = control)

    def check_invalid_mixer_ranges(self):
        """
        Check to make sure that any invalid values for a mixer control cannot be
        set.

        """
        audio_manager = self.work_node.get_audio_component_manager()
        soundcards = audio_manager.get_soundcards()
        if soundcards == []:
            raise TestFailure("Unable to find any soundcards on the work node")
        for soundcard in soundcards:
            controls = soundcard.get_controls()
            mixer_controls = []
            for control in controls:
                if control.get_interface() == 'MIXER' and not control.is_read_only():
                    self.__check_invalid_control_range(control = control)

    def check_setting_same_mixer_value(self):
        """
        Check to make sure that we can set the mixer control to the same value
        it is currently set to.

        """
        audio_manager = self.work_node.get_audio_component_manager()
        soundcards = audio_manager.get_soundcards()
        if soundcards == []:
            raise TestFailure("Unable to find any soundcards on the work node")
        for soundcard in soundcards:
            controls = soundcard.get_controls()
            mixer_controls = []
            for control in controls:
                if control.get_interface() == 'MIXER' and not control.is_read_only():
                    self.__check_setting_same_mixer_value(control = control)

    def __check_valid_control_range(self, control):
        if control.get_type() == 'INTEGER':
            self.__check_valid_integer_control_range(control = control)
        elif control.get_type() == 'BOOLEAN':
            self.__check_valid_boolean_control_range(control = control)
        elif control.get_type() == 'ENUMERATED':
            self.__check_valid_enumerated_control_range(control = control)

    def __check_invalid_control_range(self, control):
        if control.get_type() == 'INTEGER':
            self.__check_invalid_integer_control_range(control = control)
        elif control.get_type() == 'BOOLEAN':
            self.__check_invalid_boolean_control_range(control = control)
        elif control.get_type() == 'ENUMERATED':
            self.__check_invalid_enumerated_control_range(control = control)

    def __check_setting_same_mixer_value(self, control):
        if control.get_type() == 'INTEGER':
            self.__check_setting_integer_control_same_value(control = control)
        elif control.get_type() == 'BOOLEAN':
            self.__check_setting_boolean_control_same_value(control = control)
        elif control.get_type() == 'ENUMERATED':
            self.__check_setting_enumerated_control_same_value(control = control)

    def __check_valid_integer_control_range(self, control):
        minimum = control.get_minimum_value()
        maximum = control.get_maximum_value()
        original_values = control.get_values()
        increasing_range = list(range(minimum, maximum + 1))
        decreasing_range = list(range(minimum, maximum + 1))
        random_range = list(range(minimum, maximum + 1))
        decreasing_range.reverse()
        random = self.get_random_module()
        random.shuffle(random_range)
        # Set the values between the minimum and maximum: increasing,
        # decreasing, and random
        for value_range in [increasing_range, decreasing_range, random_range]:
            for value in value_range:
                self.get_logger().info(
                    "Set volume of {control} to {value}".format(
                        control = control.get_name(),
                        value = value,
                    )
                )
                control.set_volume_value(value = value)
                control_value = control.get_volume_value()
                if control_value != value:
                    raise TestFailure(
                        "Unable to set value of {control} to {value}".format(
                            control = control.get_name(),
                            value = value,
                        )
                    )
        # Set the control to the original value
        self.get_logger().info(
            "Set volume of {control} back to {value}".format(
                control = control.get_name(),
                value = original_values[0],
            )
        )
        control.set_volume_value(value = original_values[0])

    def __check_invalid_integer_control_range(self, control):
        maximum = control.get_maximum_value()
        original_value = control.get_volume_value()
        # Try to set the control value above the maximum
        self.get_logger().info(
            "Attempt to set volume of {control} to {value} (shouldn't work)".format(
                control = control.get_name(),
                value = maximum + 1,
            )
        )
        control.set_raw_value(value = maximum + 1)
        control_value = control.get_volume_value()
        if control_value > maximum:
            raise TestFailure(
                "Able to set value of {control} to value {value} when maximum is {maximum}".format(
                    control = control.get_name(),
                    value = control_value,
                    maximum = maximum,
                )
            )
        # Set the control to the original value
        self.get_logger().info(
            "Set volume of {control} back to {value}".format(
                control = control.get_name(),
                value = original_value,
            )
        )
        control.set_volume_value(value = original_value)

    def __check_setting_integer_control_same_value(self, control):
        original_value = control.get_volume_value()
        # Set the control to the same value
        self.get_logger().info(
            "Set volume of {control} from {value} to {value}".format(
                control = control.get_name(),
                value = original_value,
            )
        )
        control.set_volume_value(value = original_value)
        control_value = control.get_volume_value()
        if control_value != original_value:
            raise TestFailure(
                "Unable to set value of {control} to {value} from {value}, showing as {new_value}".format(
                    control = control.get_name(),
                    value = original_value,
                    new_value = control_value,
                )
            )

    def __check_valid_boolean_control_range(self, control):
        original_value_is_on = control.is_on()
        # Set the control to the alternate value
        if original_value_is_on:
            self.get_logger().info(
                "Set {control} to off".format(
                    control = control.get_name(),
                )
            )
            control.set_off()
            if control.is_on():
                raise TestFailure(
                    "Unable to set {control} to off from on".format(
                        control = control.get_name(),
                    )
                )
        else:
            self.get_logger().info(
                "Set {control} to on".format(
                    control = control.get_name(),
                )
            )
            control.set_on()
            if control.is_off():
                raise TestFailure(
                    "Unable to set {control} to on from off".format(
                        control = control.get_name(),
                    )
                )
        # Set the control to the alternate value using numbers
        if original_value_is_on:
            self.get_logger().info(
                "Set {control} to 1".format(
                    control = control.get_name(),
                )
            )
            control.set_raw_value(value = 1)
            if control.is_off():
                raise TestFailure(
                    "Unable to set {control} to on from off by setting 1".format(
                        control = control.get_name(),
                    )
                )
        else:
            self.get_logger().info(
                "Set {control} to 0".format(
                    control = control.get_name(),
                )
            )
            control.set_raw_value(value = 0)
            if control.is_on():
                raise TestFailure(
                    "Unable to set {control} to off from on by setting 0".format(
                        control = control.get_name(),
                    )
                )
        # Set the control to the original value
        if original_value_is_on:
            self.get_logger().info(
                "Set {control} back to on".format(
                    control = control.get_name(),
                )
            )
            control.set_on()
        else:
            self.get_logger().info(
                "Set {control} back to off".format(
                    control = control.get_name(),
                )
            )
            control.set_off()

    def __check_invalid_boolean_control_range(self, control):
        original_value_is_on = control.is_on()
        # Try to set the control to a non on/off value
        self.get_logger().info(
            "Attempt to set {control} to {value} (shouldn't work)".format(
                control = control.get_name(),
                value = 'test',
            )
        )
        control.set_raw_value(value = 'test')
        new_values = control.get_values()
        if new_values[0] != 'on' and new_values[0] != 'off':
            raise TestFailure(
                "Able to set {control} to 'test'".format(
                    control = control.get_name(),
                )
            )
        # Set the control to the original value
        if original_value_is_on:
            self.get_logger().info(
                "Set {control} back to on".format(
                    control = control.get_name(),
                )
            )
            control.set_on()
        else:
            self.get_logger().info(
                "Set {control} back to off".format(
                    control = control.get_name(),
                )
            )
            control.set_off()

    def __check_setting_boolean_control_same_value(self, control):
        original_value_is_on = control.is_on()
        # Set control to the same value
        if original_value_is_on:
            self.get_logger().info(
                "Set {control} to on from on".format(
                    control = control.get_name(),
                )
            )
            control.set_on()
            if control.is_off():
                raise TestFailure(
                    "Unable to set {control} to on from on".format(
                        control = control.get_name(),
                    )
                )
        else:
            self.get_logger().info(
                "Set {control} to off from off".format(
                    control = control.get_name(),
                )
            )
            control.set_off()
            if control.is_on():
                raise TestFailure(
                    "Unable to set {control} to off from off".format(
                        control = control.get_name(),
                    )
                )

    def __check_valid_enumerated_control_range(self, control):
        original_value = control.get_enumerated_value()
        enumerated_values = control.get_enumerated_values()
        # Set the control to each enumerated value index
        for value in enumerated_values:
            self.get_logger().info(
                "Set {control} to {value} by index".format(
                    control = control.get_name(),
                    value = value,
                )
            )
            control.set_enumerated_value(value = value)
            new_value = control.get_enumerated_value()
            if new_value != value:
                raise TestFailure(
                    "Unable to set {control} to {value} by index number".format(
                        control = control.get_name(),
                        value = value,
                    )
                )
        # Set the control to each enumerated value string
        for value in enumerated_values:
            self.get_logger().info(
                "Set {control} to {value} by string".format(
                    control = control.get_name(),
                    value = "'{0}'".format(value),
                )
            )
            control.set_raw_value(value = "'{0}'".format(value))
            new_value = control.get_enumerated_value()
            if new_value != value:
                raise TestFailure(
                    "Unable to set {control} to {value}".format(
                        control = control.get_name(),
                        value = "'{0}'".format(value),
                    )
                )
        # Set the control to the original value
        self.get_logger().info(
            "Set {control} back to {value}".format(
                control = control.get_name(),
                value = original_value,
            )
        )
        control.set_enumerated_value(value = original_value)

    def __check_invalid_enumerated_control_range(self, control):
        original_value = control.get_enumerated_value()
        enumerated_values = control.get_enumerated_values()
        test_string = 'test'
        counter = 0
        # Find a value that isn't one of the enumerated values
        while test_string + str(counter) in enumerated_values:
            counter = counter + 1
        test_string = test_string + str(counter)
        self.get_logger().info(
            "Attempt to set {control} to {value} (shouldn't work)".format(
                control = control.get_name(),
                value = test_string,
            )
        )
        control.set_raw_value(value = test_string)
        new_value = control.get_enumerated_value()
        if new_value != enumerated_values[0]:
            raise TestFailure(
                "Able to set {control} to {value} without it defaulting to {default}".format(
                    control = control.get_name(),
                    value = new_value,
                    default = enumerated_values[0],
                )
            )
        # Set the control to the original value
        self.get_logger().info(
            "Set {control} back to {value}".format(
                control = control.get_name(),
                value = original_value,
            )
        )
        control.set_enumerated_value(value = original_value)

    def __check_setting_enumerated_control_same_value(self, control):
        original_value = control.get_enumerated_value()
        # Set control to the same value by index
        self.get_logger().info(
            "Set {control} from {value} to {value} by index".format(
                control = control.get_name(),
                value = original_value,
            )
        )
        control.set_enumerated_value(value = original_value)
        new_value = control.get_enumerated_value()
        if new_value != original_value:
            raise TestFailure(
                "Unable to set {control} to {value} from {value} by index number, showing as {new_value}".format(
                    control = control.get_name(),
                    value = original_value,
                    new_value = new_value,
                )
            )
        # Set control to same value by string
        self.get_logger().info(
            "Set {control} from {value} to {value} by string".format(
                control = control.get_name(),
                value = "'{0}'".format(original_value),
            )
        )
        control.set_raw_value(value = "'{0}'".format(original_value))
        new_value = control.get_enumerated_value()
        if new_value != original_value:
            raise TestFailure(
                "Unable to set {control} to {value} from {value}, showing as {new_value}".format(
                    control = control.get_name(),
                    value = "'{0}'".format(original_value),
                    new_value = new_value,
                )
            )

if __name__ == '__main__':
    exit(Test().run_test())
