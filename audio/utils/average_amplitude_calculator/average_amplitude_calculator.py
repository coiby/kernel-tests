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

class AverageAmplitudeCalculator(object):
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
            dest = 'file',
            action = 'store',
            help = 'wav file to find the average amplitude of',
        )

    def _get_file_name(self):
        """
        Get the file name to get the amplitude of

        Return value:
        String of the file name.

        """
        (options, args) = self.__get_command_line_option_parser().parse_args()
        return options.file

    def run_test(self):
        """
        For the provided wav files compare the average frequency.

        """
        file_name = self._get_file_name()
        wav_file_info = {}

        # Read in the wav files
        print("Reading file {file_name}".format(file_name = file_name))
        rate, data = scipy.io.wavfile.read(file_name)
        wav_file_info = {
            'file_name': file_name,
            'sample_rate': rate,
            'file_data': data,
            'amplitude': None,
        }

        # Calculate the amplitude for the wav
        track = None
        if len(wav_file_info['file_data'].shape) == 1:
            track = wav_file_info['file_data']
        elif len(wav_file_info['file_data'].shape) > 1:
            track = wav_file_info['file_data'].T[0]
        else:
            raise Exception(
                "Unable to determine the number of channels within {file_name}".format(
                    file_name = wav_file_info['file_name'],
                )
            )
        amplitude_in_db = 20 * numpy.log10(numpy.sqrt(numpy.mean(track)))
        wav_file_info['amplitude'] = amplitude_in_db
        print(
            "File: {file_name}, amplitude: {amplitude} db".format(
                file_name = wav_file_info['file_name'],
                amplitude = wav_file_info['amplitude'],
            )
        )

        return 0

if __name__ == '__main__':
    exit(AverageAmplitudeCalculator().run_test())
