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
The worknode.linux.util.wget module provides a class (wget) that represents the
executable used to download a remote file over http.

"""

__author__ = 'Ken Benoit'

import re

import worknode.worknode_executable
from worknode.exception.worknode_executable import *
from constants.time import *

class wget(worknode.worknode_executable.WorkNodeExecutable):
    """
    wget represents the command used to download a remote file over http.

    """
    def __init__(self, work_node, command = 'wget'):
        super(wget, self).__init__(work_node)
        self.__command = command
        self.__failure_regexes = []
        self.__local_file_regex = None
        self.__output_file_path = None
        self.__output_file_option = None
        self.add_failure_regular_expression(regex = 'ERROR')
        self.set_output_file_option(option = '--output-document')

    def add_failure_regular_expression(self, regex):
        """
        Add a regular expression that indicates command failure.

        Keyword arguments:
        regex - Regular expression indicating command failure.

        """
        self.__failure_regexes.append(regex)

    def set_local_file_regular_expression(self, regex):
        """
        Set a regular expression that indicates what the local file name is.

        Keyword arguments:
        regex - Regular expression for getting the name of the downloaded file.
                Make sure to put a regex grouping around the file name in the
                format of (?P<file_name>)

        """
        self.__local_file_regex = regex

    def set_output_file_option(self, option):
        """
        Set the option to be provided for supplying an output file location.

        Keyword arguments:
        option - Command-line option for supplying the output file location.

        """
        self.__output_file_option = option

    def run_command(self, file_path, output_file_path = None, timeout = HOUR):
        """
        Run the command.

        Keyword arguments:
        file_path - Path to the remote file.
        output_file_path - Path to the file after downloaded on the local
                           system.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        Return value:
        Path to the downloaded file.

        """
        file_name = None
        full_command = self.__command
        if output_file_path is not None:
            full_command = ' '.join(
                [
                    full_command,
                    self.__output_file_option,
                    output_file_path,
                ]
            )
        full_command = ' '.join([full_command, file_path])
        output = super(wget, self)._run_command(command = full_command, timeout = timeout)
        found_failure = False
        joined_output = ''.join(output)
        for fail_regex in self.__failure_regexes:
            if re.search(fail_regex, joined_output):
                found_failure = True
                break
        if found_failure:
            raise FailedCommandOutputError("wget failed to download the file")
        match = re.search(self.__local_file_regex, joined_output)
        if not match:
            raise FailedCommandOutputError("Failed to find the local file name provided by wget")
        file_name = match.group('file_name')
        if file_name is None:
            raise FailedCommandOutputError("Failed to find the local file name provided by wget")
        return file_name

    def download_file(self, file_path, output_file_path = None, timeout = HOUR):
        """
        Download the specified file using wget.

        Keyword arguments:
        file_path - Path to the remote file.
        output_file_path - Path to the file after downloaded on the local
                           system.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        Return value:
        Path to the downloaded file.

        """
        file_path = self.run_command(
            file_path = file_path,
            output_file_path = output_file_path,
            timeout = timeout,
        )
        return file_path
