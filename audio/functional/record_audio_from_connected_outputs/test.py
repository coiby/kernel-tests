#!/usr/bin/python
# Copyright (c) 2018 Red Hat, Inc. All rights reserved. This copyrighted material
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
The functional.record_audio_from_connected_outputs.test module provides a class
(Test) that finds all audio outputs on a system and records the audio from those
outputs. It performs an average frequency comparison between the target
frequency and the recorded input file.

"""

__author__ = 'Ken Benoit'

import re
import time

import base.test
import worknode.worknode_factory
from base.exception.test import *
from worknode.linux.manager.exception.file_system import *

class Test(base.test.Test):
    """
    Test performs an audio test where all connected audio output jacks have
    audio files played through them and record those audio jacks to make sure
    audio plays correctly.

    """
    def __init__(self):
        super(Test, self).__init__()
        # Set up the test information
        self.set_test_name(
            name = '/kernel/audio_tests/functional/record_audio_from_connected_outputs',
        )
        self.set_test_author(name = 'Ken Benoit', email = 'kbenoit@redhat.com')
        self.set_test_description(
            description = 'Test to play audio over the loopback cable of all '
                + 'connected outputs.',
        )
        self.__configure_test_command_line_options()
        self.__configure_test_steps()
        # Set up test variables
        self.work_node = None
        self.input_sources = []
        self.input_switches = []
        self.input_volumes = []
        self.input_volume_names = ['Input Volume', 'Capture Volume']
        self.input_source_names = ['Input Source', 'Capture Source']
        self.input_switch_names = ['Input Switch', 'Capture Switch']
        self.inputs = []
        self.output_switches = []
        self.output_volumes = []
        self.output_volume_names = ['Playback Volume']
        self.output_switch_names = ['Playback Switch']
        self.master_output_volume_names = ['Master Playback Volume']
        self.master_output_switch_names = ['Master Playback Switch']
        self.outputs = []
        self.audio_map = []

    def __configure_test_command_line_options(self):
        self.add_command_line_option(
            '--skip-control',
            dest = 'skip_controls',
            action = 'append',
            default = [],
            help = 'skip jack detection on the specified control (in the '
                + 'format of "card_number:control_number". can be specified '
                + 'multiple times',
        )
        self.add_command_line_option(
            '--test-frequency',
            dest = 'test_frequencies',
            action = 'append',
            default = [],
            help = 'specific frequency to test instead of randomized '
                + 'frequencies. can be specified multiple times',
        )
        self.add_command_line_option(
            '--confirm-zero',
            dest = 'confirm_zero',
            action = 'store_true',
            default = False,
            help = 'confirm that the opposite channel not under test shows 0 Hz',
        )

    def __configure_test_steps(self):
        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.play_and_record_audio,
            test_step_description = 'Play audio through all connected outputs '
                + 'and record it on the matching inputs',
        )

    def get_work_node(self):
        """
        Generate a work node object to use for the test.

        """
        self.work_node = worknode.worknode_factory.WorkNodeFactory().get_work_node()

    def _play_frequency(self, frequency, channel, max_channels, playback_control):
        """
        Play a frequency over a specific channel for a specific jack.

        Keyword arguments:
        frequency - Frequency (in Hz) to play over the output channel.
        channel - Channel number (1+) to play the frequency over.
        max_channels - The maximum number of channels supported by the output.
        playback_control - Object representing the playback control to output
                           through.

        Return values:
        Process object.

        """
        playback_card = playback_control._get_soundcard()
        playback_card_number = playback_card.get_index()
        playback_device_number = self._get_device_number(playback_control)
        process = self.work_node.start_process(
            command = "speaker-test --device plughw:{playback_card_number},{playback_device_number} --channels {max_channels} --speaker {channel} --test sine --frequency {frequency}".format(
                playback_card_number = playback_card_number,
                playback_device_number = playback_device_number,
                max_channels = max_channels,
                channel = channel,
                frequency = frequency,
            )
        )
        return process

    def _record_frequency(self, capture_control):
        """
        Record a frequency for a specific jack.

        Keyword arguments:
        capture_control - Object representing the capture control to record
                          through.

        Return values:
        Process object.

        """
        capture_card = capture_control._get_soundcard()
        capture_card_number = capture_card.get_index()
        capture_device_number = self._get_device_number(capture_control)
        # Something to note about this call. arecord has a command line flag,
        # "--separate-channels" that is supposed to give you the ability to
        # list a number of files to write out to, with each channel going to a
        # separate file. In usage, this does not appear to output wav file data
        # which makes it useless to try to verify the frequency of the files
        # thereafter. Hence, here, we record a stereo (2-channel) wav file that
        # we later use sox to split into a wav file for each channel.
        process = self.work_node.start_process(
            command = "arecord --device plughw:{capture_card_number},{capture_device_number} --format dat --channels 2 --duration 5 stereo.wav".format(
                capture_card_number = capture_card_number,
                capture_device_number = capture_device_number,
            )
        )
        return process

    def _record_frequency_rhel8(self, capture_control):
        """
        Record a frequency for a specific jack.

        Keyword arguments:
        capture_control - Object representing the capture control to record
                          through.

        Return values:
        Process object.

        """
        capture_card = capture_control._get_soundcard()
        capture_card_number = capture_card.get_index()
        capture_device_number = self._get_device_number(capture_control)
        # Unlike arecord in RHEL6 and RHEL7, newly introduced command axfer
        # actually has a functional --separate-channels option. Use this since
        # sox is no longer available in RHEL8 for separating the channels into
        # different wav files.
        process = self.work_node.start_process(
            command = "axfer transfer capture --device plughw:{capture_card_number},{capture_device_number} --format dat --channels 2 --duration 5 --separate-channels test.wav".format(
                capture_card_number = capture_card_number,
                capture_device_number = capture_device_number,
            )
        )
        return process

    def _separate_channels(self, stereo_file):
        """
        Take in a file object of a stereo wav file and then separate it out into
        two wav files representing the left and right channels.

        Keyword arguments:
        stereo_file - File object that represents a stereo wav file.

        """
        # Since "arecord --separate channels" does not appear to put out a wav
        # file for each channel we turn to sox which has a number of options it
        # can do with sound files. In this case we can specify the remix option
        # to take an initial wav file and output to a new wav file that includes
        # just a single channel. We can use this to take a 2-channel wav file
        # and get the left and right channels out of it.
        self.work_node.run_command(
            command = "sox {stereo_file} 0.wav remix 1".format(
                stereo_file = str(stereo_file),
            )
        )
        self.work_node.run_command(
            command = "sox {stereo_file} 1.wav remix 2".format(
                stereo_file = str(stereo_file),
            )
        )
        # After we split the stereo file into two mono files go through and
        # delete the stereo file since we don't need it anymore
        stereo_file.delete()

    def _play_and_record(self, frequency, channel, max_channels, playback_control, capture_control):
        """
        Play and record a frequency on specific jacks.

        Keyword arguments:
        frequency - Frequency (in Hz) to play over the output channel.
        channel - Channel number (1+) to play the frequency over.
        max_channels - The maximum number of channels supported by the output.
        playback_control - Object representing the playback control to output
                           through.
        capture_control - Object representing the capture control to record
                          through.

        """
        file_manager = self.work_node.get_file_system_component_manager()
        left_wav = None
        right_wav = None
        record_process = None
        # Ensure we make audio playback possible
        self._setup_output_controls(output_control = playback_control)
        # Ensure we make audio capture possible
        self._setup_input_controls(input_control = capture_control)
        # Play out the specified frequency, grabbing the process object so that
        # we can start the record process at near the same time
        play_process = self._play_frequency(
            frequency = frequency,
            channel = channel,
            max_channels = max_channels,
            playback_control = playback_control,
        )
        if self.work_node.get_major_version() < 8:
            # Start recording on the capture control
            record_process = self._record_frequency(
                capture_control = capture_control,
            )
        else:
            # Start recording on the capture control
            record_process = self._record_frequency_rhel8(
                capture_control = capture_control,
            )
        # Wait for the playback to complete
        while play_process.is_running():
            time.sleep(1)
        # Wait for the recording to complete
        while record_process.is_running():
            time.sleep(1)
        # Set the output controls back to their initial values
        self._restore_output_controls()
        # Set the input controls back to their initial values
        self._restore_input_controls()
        if self.work_node.get_major_version() < 8:
            stereo_wav = file_manager.get_file(file_path = 'stereo.wav')
            # Separate the stereo wav into left and right channels
            self._separate_channels(stereo_file = stereo_wav)
            left_wav = file_manager.get_file(
                file_path = '0.wav',
            )
            right_wav = file_manager.get_file(
                file_path = '1.wav',
            )
        else:
            left_wav = file_manager.get_file(
                file_path = 'test-0.wav',
            )
            right_wav = file_manager.get_file(
                file_path = 'test-1.wav',
            )
        return {
            'left': left_wav,
            'right': right_wav,
        }

    def _is_frequency_similar(self, frequency, wav_file):
        """
        Compare the provided wav file against the frequency.

        Keyword arguments:
        frequency - Frequency to compare against.
        wav_file - File object that contains the path to the wav file to compare
                   against.

        Return values:
        True if the wav file is similar to the frequency provided. False if the
        wav file is not similar to the frequency provided.

        """
        file_manager = self.work_node.get_file_system_component_manager()
        compare_audio_script = file_manager.get_file(
            file_path = 'compare_audio.sh',
        )
        output = self.work_node.run_command(
            command = '{script_name} {frequency} {wav_file}'.format(
                script_name = str(compare_audio_script),
                frequency =  str(frequency),
                wav_file = str(wav_file),
            )
        )
        if re.search('frequency difference', ''.join(output)):
            return False
        return True

    def _setup_output_controls(self, output_control):
        """
        Setup the output controls so that the output switches are turned on (if
        they aren't already) and max out the volume on the output volume
        controls.

        Keyword arguments:
        output_control - Output jack control on the soundcard that should be set
                         as the output source.

        """
        soundcard = output_control._get_soundcard()
        output_control_name = ''
        # Get the name of the playback control without the "Jack" portion, since
        # all of the associated switch and volume controls use the name of the
        # playback control without the "Jack" addendum
        match = re.search("(?P<control_name>.*?) Jack", output_control.get_name())
        if not match:
            raise TestFailure("Unable to determine name of {output_control}".format(
                    output_control = output_control.get_name(),
                )
            )
        output_control_name = match.group('control_name')
        for control in soundcard.get_controls():
            for switch_name in self.output_switch_names:
                specific_switch_name = output_control_name + ' ' + switch_name
                # If the control matches the jack-specific switch name
                if control.get_name() == specific_switch_name:
                    # Save off if the initial setting was on
                    self.output_switches.append(
                        {
                            'control': control,
                            'starting_setting_is_on': control.is_on(),
                        }
                    )
                    # Set the output switch on
                    control.set_on()
            for switch_name in self.master_output_switch_names:
                # If the control matches a generic master playback switch name
                if control.get_name() == switch_name:
                    # Save off if the initial setting was on
                    self.output_switches.append(
                        {
                            'control': control,
                            'starting_setting_is_on': control.is_on(),
                        }
                    )
                    # Set the output switch on
                    control.set_on()
            for volume_name in self.output_volume_names:
                specific_volume_name = output_control_name + ' ' + volume_name
                # If the control matches the jack-specific volume name
                if control.get_name() == specific_volume_name:
                    # Save off the initial volume level
                    self.output_volumes.append(
                        {
                            'control': control,
                            'starting_volume': control.get_volume_value(),
                        }
                    )
                    # Set the volume level to 100%
                    control.set_volume_percentage(percent = 100)
            for volume_name in self.master_output_volume_names:
                # If the control matches the generic master playback volume name
                if control.get_name() == volume_name:
                    # Save off the initial volume level
                    self.output_volumes.append(
                        {
                            'control': control,
                            'starting_volume': control.get_volume_value(),
                        }
                    )
                    # Set the volume level to 100%
                    control.set_volume_percentage(percent = 100)

    def _setup_input_controls(self, input_control):
        """
        Setup the input controls so that the input switches are turned on (if
        they aren't already), max out the volume on the input volume
        controls, and set the input source controls to use the selected input
        control as the default input control.

        Keyword arguments:
        input_control - Input jack control on the soundcard that should be set
                        as the input source.

        """
        soundcard = input_control._get_soundcard()
        for control in soundcard.get_controls():
            # If the control matches an input source control
            if control.get_name() in self.input_source_names:
                # Save off what the initial source was
                self.input_sources.append(
                    {
                        'control': control,
                        'starting_source': control.get_enumerated_value(),
                    }
                )
                match = re.search('(?P<control_name>.+) Jack', input_control.get_name())
                # Set the input source to the selected capture jack
                control.set_enumerated_value(
                    value = match.group('control_name'),
                )
            # If the control matches an input switch control
            elif control.get_name() in self.input_switch_names:
                # Save off if the initial setting was on
                self.input_switches.append(
                    {
                        'control': control,
                        'starting_setting_is_on': control.is_on(),
                    }
                )
                # Set the input switch to on
                control.set_on()
            # If the control matches an input volume control
            elif control.get_name() in self.input_volume_names:
                # Save off the initial volume level
                self.input_volumes.append(
                    {
                        'control': control,
                        'starting_volume': control.get_volume_value(),
                    }
                )
                # Set the input volume to 100%
                control.set_volume_percentage(percent = 100)

    def _restore_output_controls(self):
        """
        Restore the output controls back to their initial settings (turn off the
        output switches if they were initially turned off and lower the volume
        on the output volume controls to their initial levels).

        """
        # Set all the output switch controls back to their initial settings
        for control_dictionary in self.output_switches:
            control = control_dictionary['control']
            starting_setting_is_on = control_dictionary['starting_setting_is_on']
            if not starting_setting_is_on:
                control.set_off()
        # Clear out our list of output switch controls
        self.output_switches = []
        # Set all the output volume controls back to their initial levels
        for control_dictionary in self.output_volumes:
            control = control_dictionary['control']
            starting_volume = control_dictionary['starting_volume']
            control.set_volume_value(value = starting_volume)
        # Clear out our list of input volume controls
        self.output_volumes = []

    def _restore_input_controls(self):
        """
        Restore the input controls back to their initial settings (turn off the
        input switches if they were initially turned off, lower the volume on
        the input volume controls to their initial levels, and set the input
        source back to the initial input control).

        """
        # Set all the input source controls back to their initial settings
        for control_dictionary in self.input_sources:
            control = control_dictionary['control']
            starting_source = control_dictionary['starting_source']
            control.set_enumerated_value(
                value = starting_source,
            )
        # Clear out our list of input source controls
        self.input_sources = []
        # Set all the input switch controls back to their initial settings
        for control_dictionary in self.input_switches:
            control = control_dictionary['control']
            starting_setting_is_on = control_dictionary['starting_setting_is_on']
            if not starting_setting_is_on:
                control.set_off()
        # Clear out our list of input switch controls
        self.input_switches = []
        # Set all the input volume controls back to their initial levels
        for control_dictionary in self.input_volumes:
            control = control_dictionary['control']
            starting_volume = control_dictionary['starting_volume']
            control.set_volume_value(value = starting_volume)
        # Clear out our list of input volume controls
        self.input_volumes = []

    def _get_active_audio_controls(self):
        """
        Generate a list of all active audio controls (audio jacks that currently
        have a cable attached).

        """
        skip_controls = self.get_command_line_option_value(
            dest = 'skip_controls',
        )
        audio_manager = self.work_node.get_audio_component_manager()
        # Go through all the soundcards in the system
        for soundcard in audio_manager.get_soundcards():
            # Go through all the soundcard controls
            for control in soundcard.get_controls():
                # Make sure it's a card control (meaning it should be a physical
                # jack)
                if control.get_interface() == 'CARD':
                    # Check if the control is on (meaning a cable is connected)
                    # and skip any "phantom" jacks
                    if control.is_on() and not re.search('[Pp]hantom', control.get_name()):
                        if len(skip_controls) > 0:
                            for control_details in skip_controls:
                                card_number, control_number = control_details.split(":")
                                if card_number is None or control_number is None:
                                    raise TestFailure(
                                        "Control to skip '{}' has been specified incorrectly".format(
                                            control_details
                                        )
                                    )
                                if not soundcard.get_index() == int(card_number) and not control.get_id() == int(control_number):
                                    # Check if the jack is a mic
                                    if re.search('[Mm]ic', control.get_name()):
                                        # If it is then add it to our list of inputs
                                        self.inputs.append(control)
                                    else:
                                        # If it isn't a mic then it must be an output
                                        self.outputs.append(control)
                        else:
                            # Check if the jack is a mic
                            if re.search('[Mm]ic', control.get_name()):
                                # If it is then add it to our list of inputs
                                self.inputs.append(control)
                            else:
                                # If it isn't a mic then it must be an output
                                self.outputs.append(control)

    def _get_device_number(self, control):
        """
        Get the device number of a given jack.

        Keyword arguments:
        control - SoundcardControl object of the jack.

        Return value:
        Integer of the device number of the jack.

        """
        # If there are multiple devices then if they are not device 0 they will
        # be listed as "pcm=" followed by the device number. Device 0 is always
        # just assumed, so if we don't have "pcm=" then that device is device 0.
        device_number = None
        match = re.search('pcm=(?P<device_number>\d+)', control.get_name())
        if match:
            device_number = int(match.group('device_number'))
        else:
            device_number = 0
        return device_number

    def _get_matching_playback_channel_map(self, playback_control):
        """
        Given a playback control object find the matching playback channel map
        control object.

        Keyword arguments:
        playback_control - SoundcardControl object of the playback jack control.

        Return value:
        SoundcardControl object of the playback channel map control.

        """
        soundcard = playback_control._get_soundcard()
        # Get the PCM number of the playback jack control
        device_number = self._get_device_number(control = playback_control)

        # Go through the controls to find a Playback Channel Map control with a
        # device number that matches the playback jack's PCM number
        for control in soundcard.get_controls():
            if control.get_name() == 'Playback Channel Map':
                if control.get_device_number() == device_number:
                    return control
        raise TestFailure(
            "Unable to find a matching Playback Channel Map control for "
            + "playback control {}".format(playback_control.get_name())
        )

    def _map_outputs_to_inputs(self):
        """
        Map audio outputs to the audio inputs that they are connected to. This
        method will go through and play a sound over each connected audio output
        and go through each connected audio input to find out which of the
        inputs is connected to the output currently playing audio.

        """
        for output_control in self.outputs:
            map_control = self._get_matching_playback_channel_map(
                playback_control = output_control,
            )
            output_map = {
                'control': output_control,
                'channel_map': map_control,
                'max_channels': 0,
                'channels': {},
            }
            # Check to see what the playback channel map is for the device since
            # this will tell us how many possible channels the device is capable
            # of outputting to. Analog outputs are generally only capable of
            # outputting 2 channels (stereo) while HDMI/DisplayPort devices can
            # be capable of outputting 6 (5.1 surround sound) or even more
            # channels (generally up to 8 channels, i.e. 7.1 surround sound).
            max_channels = 0
            for channel_map in map_control.get_channel_mappings():
                mapping = channel_map.get_map()
                if len(mapping) > max_channels:
                    max_channels = len(mapping)
            output_map['max_channels'] = max_channels
            for channel_number in range(1, max_channels + 1):
                # Loop through all the connected inputs
                for input_control in self.inputs:
                    # Play audio and record it coming in on the input
                    wavs = self._play_and_record(
                        frequency = 500,
                        channel = channel_number,
                        max_channels = max_channels,
                        playback_control = output_control,
                        capture_control = input_control,
                    )
                    # Loop through the wav files for the left and right channel
                    for wav_side in wavs.keys():
                        wav_file = wavs[wav_side]
                        if self._is_frequency_similar(frequency = 500, wav_file = wav_file):
                            output_map['channels'][channel_number] = {
                                'side': wav_side,
                                'capture_control': input_control,
                            }
                            wav_file.delete()
                            continue
                        wav_file.delete()
            if len(output_map['channels'].keys()) < 1:
                raise TestFailure(
                    "Output {output_control} appears to be connected but cannot find matching connected input. Please check loopback cabling.".format(
                        output_control = output_control.get_name(),
                    )
                )
            self.audio_map.append(output_map)

    def play_and_record_audio(self):
        """
        Play audio over all the connected output jacks and record the audio at
        the same time over the loopback cables.

        """
        manual_frequencies = self.get_command_line_option_value(
            dest = 'test_frequencies',
        )
        confirm_zero = self.get_command_line_option_value(
            dest = 'confirm_zero',
        )
        test_frequencies = []
        if len(manual_frequencies) == 0:
            random = self.get_random_module()

            # Generate a list of random frequencies to test with (making sure to get
            # a decent sampling of frequencies from the whole supported range)
            test_frequencies = [
                random.randint(300, 2000),
                random.randint(2001, 4000),
                random.randint(4001, 6000),
                random.randint(6001, 8000),
            ]
            # Randomize the list so that we're not just stepping up in frequencies
            # every test run
            random.shuffle(test_frequencies)
        else:
            for frequency_string in manual_frequencies:
                test_frequencies.append(int(frequency_string))

        number_of_tested_outputs = 0

        # Find all the connected audio inputs and outputs
        self._get_active_audio_controls()

        # Map out which outputs connect to which inputs
        self._map_outputs_to_inputs()

        # Loop through the compiled audio map and play a range of frequencies on
        # each mapping to verify that each channel can play the frequencies
        # properly
        for output_map in self.audio_map:
            # Get the output jack control object for this mapping
            output_control = output_map['control']
            # Determine the max channel number
            max_channels = output_map['max_channels']
            # Go through each of the channel numbers that have an associated
            # input jack control
            for channel_number in output_map['channels'].keys():
                # Figure out which side of the channel (left/right) to determine
                # the correct wav file to read from
                side = output_map['channels'][channel_number]['side']
                # Get the input jack control for the channel
                input_control = output_map['channels'][channel_number]['capture_control']
                for frequency in test_frequencies:
                    # Loop through the test frequencies, playing and recording
                    # each
                    self.get_logger().info(
                        "Playing frequency {frequency}Hz out over channel {channel_number} on {output_control} and recording audio on {input_control}".format(
                            frequency = frequency,
                            channel_number = channel_number,
                            output_control = output_control.get_name(),
                            input_control = input_control.get_name(),
                        )
                    )
                    number_of_tested_outputs += 1
                    wavs = self._play_and_record(
                        frequency = frequency,
                        channel = channel_number,
                        max_channels = max_channels,
                        playback_control = output_control,
                        capture_control = input_control,
                    )
                    for side_name in wavs.keys():
                        # If the side is the test channel, check if the
                        # frequency is similar
                        wav_file = wavs[side_name]
                        if side_name == side:
                            if not self._is_frequency_similar(frequency = frequency, wav_file = wav_file):
                                # If the frequency is not similar then fail out
                                # and make sure to delete the wav files
                                # generated
                                for wav_file in wavs.values():
                                    wav_file.delete()
                                raise TestFailure(
                                    "Input and output file failed to "
                                    + "compare within tolerance levels"
                                )
                        # Otherwise if the side is the opposite channel, check
                        # if the frequency is 0
                        else:
                            if confirm_zero:
                                if not self._is_frequency_similar(frequency = 0, wav_file = wav_file):
                                    # If the frequency is not similar then fail
                                    # out and make sure to delete the wav files
                                    # generated
                                    for wav_file in wavs.values():
                                        wav_file.delete()
                                    raise TestFailure(
                                        "Channel not under test should be 0Hz, "
                                        + "but isn't"
                                    )
                    # Delete out the wav files generated
                    for wav_file in wavs.values():
                        wav_file.delete()

        if number_of_tested_outputs < 1:
            raise TestFailure(
                "Unable to detect any audio output jacks with an audio cable "
                + "connected. Verify that any loopback cables are installed "
                + "correctly."
            )

if __name__ == '__main__':
    exit(Test().run_test())
