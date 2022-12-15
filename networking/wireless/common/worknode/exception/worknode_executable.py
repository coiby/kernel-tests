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
The worknode.exception.worknode_executable module provides exceptions specific
to worknode executables.

"""

__author__ = 'Ken Benoit'

class WorkNodeExecutableException(Exception):
    """
    Overall exception that all work node executable exceptions should inherit
    from.

    """
    def __init__(self, value):
        self.value = value

    def __str__(self):
        return repr(self.value)

class FailedToExecuteError(WorkNodeExecutableException):
    """
    FailedToExecuteError represents an exception when an executable fails to
    even launch.

    """

class FailedCommandOutputError(WorkNodeExecutableException):
    """
    FailedCommandOutputError represents an exception when the command has
    returned what is expected to be a failure situation.

    """

class CommandNotFoundError(WorkNodeExecutableException):
    """
    CommandNotFoundError represents an exception when the command object is not
    currently defined or can't be located.

    """

