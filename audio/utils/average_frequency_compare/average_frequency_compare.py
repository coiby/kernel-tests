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

__author__ = 'Ken Benoit'

import numpy
import numpy.fft
import scipy.signal
import scipy.io.wavfile
import optparse

class AverageFrequencyCompare(object):
    """
    Test that compares the average frequency between wav files.

    """
    def __init__(self):
        self.__option_parser = optparse.OptionParser()
        self.__configure_command_line_options()

    def __get_command_line_option_parser(self):
        return self.__option_parser

    def __configure_command_line_options(self):
        option_parser = self.__get_command_line_option_parser()

        option_parser.add_option(
            '-f',
            '--file',
            dest = 'files',
            action = 'append',
            default = [],
            help = 'wav file to find the average frequency of to compare with '
                + 'other wav files provided',
        )
        option_parser.add_option(
            '-t',
            '--tolerance',
            dest = 'tolerance',
            type = 'int',
            action = 'store',
            default = 5,
            help = 'amount of leeway to give when determining if an average '
                + 'frequency is considered to be similar enough to the average '
                + 'frequency of the other wav files',
        )
        option_parser.add_option(
            '--target-frequency',
            dest = 'target',
            type = 'int',
            action = 'store',
            default = None,
            help = 'target frequency to compare against. only needed if '
                + 'multiple files are not provided to compare against each '
                + 'other',
        )

    def run_test(self):
        """
        For the provided wav files compare the average frequency.

        """
        (options, args) = self.__get_command_line_option_parser().parse_args()
        file_names = options.files
        tolerance = options.tolerance
        target_frequency = options.target
        wav_file_info = []

        # Read in the wav files
        for file_name in file_names:
            print("Reading file {file_name}".format(file_name = file_name))
            rate, data = scipy.io.wavfile.read(file_name)
            wav_file_info.append(
                {
                    'file_name': file_name,
                    'sample_rate': rate,
                    'file_data': data,
                    'frequency': None,
                }
            )

        # Calculate the frequency for each wav
        for index in range(0, len(wav_file_info)):
            wav_dictionary = wav_file_info[index]
            track = None
            if len(wav_dictionary['file_data'].shape) == 1:
                track = wav_dictionary['file_data']
            elif len(wav_dictionary['file_data'].shape) > 1:
                track = wav_dictionary['file_data'].T[0]
            else:
                raise Exception(
                    "Unable to determine the number of channels within {file_name}".format(
                        file_name = wav_dictionary['file_name'],
                    )
                )
            rate = numpy.int64(wav_dictionary['sample_rate'])
            windowed = track * scipy.signal.blackmanharris(len(track))
            fft_data = numpy.fft.rfft(windowed)
            max_value = numpy.int64(numpy.argmax(abs(fft_data)))
            wav_dictionary['frequency'] = rate * max_value / numpy.int64(len(windowed))
            wav_file_info[index] = wav_dictionary
            print(
                "File: {file_name}, frequency: {frequency}".format(
                    file_name = wav_dictionary['file_name'],
                    frequency = wav_dictionary['frequency'],
                )
            )

        # Compare the frequencies and make sure they don't exceed the tolerance
        if target_frequency is None:
            for wav_dictionary_1 in wav_file_info:
                for wav_dictionary_2 in wav_file_info:
                    difference = abs(wav_dictionary_1['frequency'] - wav_dictionary_2['frequency'])
                    if difference > tolerance:
                        print(
                            "File {file_name_1} and file {file_name_2} have a frequency difference of {difference} which exceeds the tolerance of {tolerance}".format(
                                file_name_1 = wav_dictionary_1['file_name'],
                                file_name_2 = wav_dictionary_2['file_name'],
                                difference = difference,
                                tolerance = tolerance,
                            )
                        )
        else:
            for wav_dictionary in wav_file_info:
                difference = abs(target_frequency - wav_dictionary['frequency'])
                if difference > tolerance:
                        print(
                            "File {file_name} and target frequency {target} have a frequency difference of {difference} which exceeds the tolerance of {tolerance}".format(
                                file_name = wav_dictionary['file_name'],
                                target = target_frequency,
                                difference = difference,
                                tolerance = tolerance,
                            )
                        )
        return 0

if __name__ == '__main__':
    exit(AverageFrequencyCompare().run_test())
