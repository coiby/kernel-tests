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
The worknode.linux.manager.exception.file_system module provides a classes
modeling exception that could be raise by objects dealing with a file system.

"""

__author__ = 'Ken Benoit'

class FileException(Exception):
    """
    Exception used when there is an error interacting with a file.

    """
    def __init__(self, value):
        self.value = value

    def __str__(self):
        return repr(self.value)

class ChecksumException(FileException):
    """
    Exception used when there is an error verifying the checksum of a file.

    """

class DirectoryException(Exception):
    """
    Exception used when there is an error interacting with a directory.

    """
    def __init__(self, value):
        self.value = value

    def __str__(self):
        return repr(self.value)
