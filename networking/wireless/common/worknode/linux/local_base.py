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
The worknode.linux.local_base module provides a standard base class
(LocalLinuxWorkNode) for all local Linux work node classes to inherit from.

"""

__author__ = 'Ken Benoit'

import time
import subprocess
import signal
import re

import worknode.linux.base
from constants.time import *

class LocalLinuxWorkNode(worknode.linux.base.LinuxWorkNode):
    """
    LocalLinuxWorkNode is a standard base class for more specific local Linux
    work node classes to inherit from.

    """
    def __init__(self):
        super(LocalLinuxWorkNode, self).__init__()

    def start_process(self, command):
        """
        Run the command provided and return the process object.

        Keyword arguments:
        command - Command string.

        Return value:
        subprocess.Popen object.

        """
        self.get_logger().debug("Running command: {0}".format(command))
        # Launch the process
        process = Process(command)
        self.get_logger().debug(
            "Process pid {0}".format(process.get_process_id())
        )
        return process

    def wait_for_process(self, process, timeout = HOUR, wait_for_regex = None):
        """
        Wait for the provided process to complete and return the command output
        as a list.

        Keyword arguments:
        process - Process object to wait for.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.
        wait_for_regex - Regular expression to wait for before sending an
                         interrupt to the command.

        Return value:
        Command output in a list.

        """
        # Determine when the method started
        start_time = time.time()
        output_string = ''
        output = []
        # Check to see if the process is still running and that the timeout has
        # not been reached
        while process.is_running() and time.time() < start_time + timeout:
            # If we're waiting for a particular regular expression to show up
            if wait_for_regex is not None:
                output_line = process.get_output(suppress_logging = True)
                output = output + output_line
                if type(wait_for_regex) is list:
                    for regex in wait_for_regex:
                        if re.search(regex, ''.join(output)):
                            process.send_signal(signal_name = 'SIGINT')
                else:
                    if re.search(wait_for_regex, ''.join(output)):
                        process.send_signal(signal_name = 'SIGINT')
        # Check if the process has actually completed
        if process.get_return_code() is None:
            exception_message = (
                "Waited {0} seconds for process {1} to ".format(
                    timeout,
                    process.get_process_id(),
                ) +  "complete and it didn't, killing it"
            )
            self.get_logger().error(exception_message)
            process.kill()
            raise RuntimeError(exception_message)
        # Get the output back
        remaining_lines = process.get_output(
            all = True,
            suppress_logging = True,
        )
        output = output + remaining_lines
        output_str_lines = []
        for line in output:
            if type(line) is not str:
                line = line.decode("utf-8")
            output_str_lines.append(line)
        # Put all the output into a single string for log output
        output_string += ''.join(output_str_lines)
        self.get_logger().debug("Command output: {0}".format(output_string))
        return output_str_lines

    def run_command(self, command, timeout = HOUR, wait_for_regex = None):
        """
        Run the provided command and return the command output as a list.

        Keyword arguments:
        command - Command string.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.
        wait_for_regex - Regular expression to wait for before sending an
                         interrupt to the command.

        Return value:
        Command output in a list.

        """
        process = self.start_process(command)
        output = self.wait_for_process(process, timeout, wait_for_regex)
        return output

class Process(worknode.linux.base.Process):
    def __init__(self, command):
        super(Process, self).__init__(command = command)
        self._set_process(
            process = subprocess.Popen(
                command,
                shell = True,
                stdout = subprocess.PIPE,
                stdin = subprocess.PIPE,
                stderr = subprocess.STDOUT,
            )
        )
        self.__available_signals = {
            'SIGABRT': signal.SIGABRT,
            'SIGFPE': signal.SIGFPE,
            'SIGILL': signal.SIGILL,
            'SIGINT': signal.SIGINT,
            'SIGSEGV': signal.SIGSEGV,
            'SIGTERM': signal.SIGTERM,
        }

    def is_running(self):
        """
        Check if the process is still running.

        Return value:
        True if process is still running. False if process has stopped.

        """
        if self._get_process().poll() is not None:
            return False
        return True

    def get_process_id(self):
        """
        Get the process ID (PID) of the process.

        Return value:
        PID string.

        """
        return self._get_process().pid

    def send_signal(self, signal_name):
        """
        Send a named signal to an already running process.

        Keyword arguments:
        signal_name - String name of the signal to send to the process.

        """
        signal_name = str(signal_name).upper()
        if signal_name not in self.__available_signals:
            raise Exception(
                "{signal_name} is not an available signal".format(
                    signal_name = signal_name,
                )
            )
        self._get_process().send_signal(self.__available_signals[signal_name])

    def send_input(self, input):
        """
        Send an input string to an already running process.

        Keyword arguments:
        input - String of text to send to the process.

        """
        input = str(input)
        # Check to see if the process is still running
        if not self.is_running():
            raise Exception(
                "Unable to submit input to process with PID {0}".format(
                    self.get_process_id()
                ) + " since it is no longer running"
            )
        # Log the input and what command it is being submitted to
        self.get_logger().debug(
            "Input for command {command} (PID {pid}): {input}".format(
                command = self.get_command(),
                pid = self.get_process_id(),
                input = input,
            )
        )
        # Write the input to stdin of the process
        self.__process.stdin.write(input)
        # Flush the write buffer to make sure the input is immediately sent
        self.__process.stdin.flush()

    def get_output(self, all = False, suppress_logging = False):
        """
        Get a list of lines of output from the process.

        Keyword arguments:
        all - If True, get all lines of output from the process. If the process
              is still running then this call will block until the process has
              finished. Otherwise this call will get output one line for every
              call made to this method.

        Return value:
        List of lines of output from the process.

        """
        output = []
        if all:
            output = output + self._get_process().stdout.readlines()
        else:
            output = output + [self._get_process().stdout.readline()]
        if not suppress_logging:
            self.get_logger().debug(
                "Command output: {0}".format(''.join(output))
            )
        return output

    def kill(self):
        """
        Stop the process from running without waiting for it to finish.

        """
        if not self.is_running() and self.get_return_code() is not None:
            raise Exception(
                "Unable to kill process with PID {0}".format(
                    self.get_process_id()
                ) + " since it is no longer running"
            )
        self._get_process().kill()

    def get_return_code(self):
        """
        Get the return code from the completed process.

        Return value:
        Return code.

        """
        return self._get_process().returncode
