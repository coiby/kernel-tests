#!/usr/bin/python
# Copyright (c) 2017 Red Hat, Inc. All rights reserved. This copyrighted material
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
The worknode.linux.util.dbus_send module provides a class (dbus_send) that
represents the dbus-send command line executable.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_executable

class dbus_send(worknode.worknode_executable.WorkNodeExecutable):
    """
    dbus_send represents the dbus-send command line executable, which provides a
    command line method for sending messages across DBus.

    """
    def __init__(self, work_node, command = 'dbus-send'):
        super(dbus_send, self).__init__(work_node)
        self.__command = command

    def get_command(self, command_arguments = None):
        """
        Get the command to execute.

        Keyword arguments:
        command_arguments - Argument string to feed to the command.

        Return value:
        Command string.

        """
        full_command = self.__command
        if command_arguments is not None:
            full_command += ' ' + command_arguments
        return full_command

    def run_command(self, command_arguments = None, timeout = 30):
        """
        Run the command and return any output.

        Keyword arguments:
        command_arguments - Argument string to feed to the command.
        timeout - Maximum timespan (in seconds) to wait for the process to
                  finish execution.

        Return value:
        Command output.

        """
        full_command = self.get_command(command_arguments = command_arguments)
        output = super(dbus_send, self)._run_command(
            command = full_command,
            timeout = timeout,
        )
        return output

    def send_message(
        self,
        object_path,
        interface,
        arguments = [],
        bus = 'session',
        message_type = 'signal',
        destination = None,
        reply_timeout = None,):
        """
        Send a message to the message bus.

        Keyword arguments:
        object_path - Path to the DBus object that you want to use for sending
                      the message.
        interface - Method/signal to use for sending the message on the bus.
        arguments - A list of arguments to send in the message, in the form of:
                    "<type>:<value>" (there are other ways to write the
                    arguments and you should refer to the documentation for
                    dbus-send for the full description).
        bus - The bus to send the message on. Can be either "session" or
              "system". Defaults to "session".
        message_type - The type of message to send. Can be either "method_call"
                       or "signal". Defaults to "signal".
        destination - The name of the connection that will receive the message.
        reply_timeout - The maximum amount of time (in milliseconds) to wait for
                        a reply.

        Return value:
        Message reply string, if any.

        """
        print_reply = None
        # Make sure the specified bus is one of the two available
        if bus != 'session' and bus != 'system':
            raise Exception("bus needs to be either 'session' or 'system'")
        # Add dashes to the bus to make it into an argument
        bus = "--" + bus

        # Make sure the specified type is one of the two available
        if message_type != 'signal' and message_type != 'method_call':
            raise Exception(
                "message_type needs to be either 'signal' or 'method_call'"
            )
        if message_type == 'method_call':
            print_reply = '--print-reply'
        # Format the message type to make it into an argument
        message_type = '--type=' + message_type

        # If arguments is not a list then raise an exception
        if type(arguments) is not list:
            raise Exception("arguments needs to be of type list")

        # If we have a destination then format it into an argument
        if destination is not None:
            destination = '--dest=' + str(destination)

        # If we have a reply timeout then format it into an argument
        if reply_timeout is not None:
            reply_timeout = '--reply-timeout ' + str(reply_timeout)

        dbus_send_arguments = [
            bus,
            destination,
            print_reply,
            reply_timeout,
            message_type,
            object_path,
            interface,
        ]

        # Loop through each of the arguments to create most of the command line
        dbus_argument_string = ''
        for argument in dbus_send_arguments:
            if argument is not None:
                dbus_argument_string = \
                    ' '.join([dbus_argument_string, argument])

        # Add the list of command line arguments to the dbus-send command so we
        # have the full command
        full_command = self.get_command(
            command_arguments = dbus_argument_string + ' ' + ' '.join(arguments)
        )
        # Run the dbus-send command and gather whatever output there is
        output = super(dbus_send, self)._run_command(command = full_command)
        return output
