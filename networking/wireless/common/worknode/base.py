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
The worknode.base module provides a standard base class (WorkNodeBase) for all
work node classes to inherit from.

"""

__author__ = 'Ken Benoit'

import sys

import framework
from constants.time import *

class WorkNodeBase(framework.Framework):
    def __init__(self):
        super(WorkNodeBase, self).__init__()
        self.__component_managers = {}

    def start_process(self, command):
        """
        Abstract method: Run the command provided and return the process object.

        Keyword arguments:
        command - Command string.

        """
        raise NotImplementedError

    def wait_for_process(self, process, timeout = HOUR):
        """
        Abstract method: Wait for the provided process to complete and return
        the command output as a list.

        Keyword arguments:
        process - Process object to wait for.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        """
        raise NotImplementedError

    def run_command(self, command, timeout = HOUR, wait_for_regex = None):
        """
        Abstract method: Run the provided command and return the command output
        as a list.

        Keyword arguments:
        command - Command string.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.
        wait_for_regex - Regular expression to wait for before sending an
                         interrupt to the command.

        """
        raise NotImplementedError

    def _add_component_manager(self, component_name, manager_class, manager_module):
        self.__component_managers[component_name] = {
            'manager_module': manager_module,
            'manager_class': manager_class,
            'manager_object': None,
            'initialized': False,
        }

    def _get_component_manager(self, component_name):
        if component_name not in self.__component_managers:
            raise NameError("Manager object for {0} doesn't exist".format(component_name))
        if not self.__component_managers[component_name]['initialized']:
            manager_module = \
                self.__component_managers[component_name]['manager_module']
            manager_class = \
                self.__component_managers[component_name]['manager_class']
            # Dynamically import the proper manager module
            manager_instance = None
            try:
                # Use importlib if possible (preferred method for Python3)
                import importlib
                module = importlib.import_module(manager_module)
                manager_instance = getattr(module, manager_class)(
                    parent = self,
                )
            except ImportError:
                # If importlib is not available then this method will work in a
                # pinch
                map(__import__, [manager_module])
                # Return an instantiation of the work node class
                manager_instance = \
                    getattr(sys.modules[manager_module], manager_class)(
                        parent = self,
                    )
            if manager_instance is None:
                raise TypeError("Unable to instantiate component manager")
            self.__component_managers[component_name]['manager_object'] = \
                manager_instance
            self.__component_managers[component_name]['initialized'] = True
        return self.__component_managers[component_name]['manager_object']

    def __repr__(self):
        return '{module}.{class_name}()'.format(module = self.__module__, class_name = self.__class__.__name__)

class Process(framework.Framework):
    def __init__(self, command):
        super(Process, self).__init__()
        self.__command = command
        self.__process = None

    def get_command(self):
        return self.__command

    def _set_process(self, process):
        self.__process = process

    def _get_process(self):
        return self.__process

    def is_running(self):
        """
        Check if the process is still running.

        Return value:
        True if process is still running. False if process has stopped.

        """
        raise NotImplementedError

    def get_process_id(self):
        """
        Get the process ID (PID) of the process.

        Return value:
        PID string.

        """
        raise NotImplementedError

    def send_signal(self, signal_name):
        """
        Send a named signal to an already running process.

        Keyword arguments:
        signal_name - String name of the signal to send to the process.

        """
        raise NotImplementedError

    def send_input(self, input):
        """
        Send an input string to an already running process.

        Keyword arguments:
        input - String of text to send to the process.

        """
        raise NotImplementedError

    def get_output(self, all = False):
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
        raise NotImplementedError

    def kill(self):
        """
        Stop the process from running without waiting for it to finish.

        """
        raise NotImplementedError

    def get_return_code(self):
        """
        Get the return code from the completed process.

        Return value:
        Return code.

        """
        raise NotImplementedError
