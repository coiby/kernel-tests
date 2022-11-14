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
The exported_file module provides a standard base class (ExportedFile) for all
exported file objects to inherit from.

"""

__author__ = 'Ken Benoit'

import framework

class ExportedFile(framework.Framework):
    """
    ExportedFile represents exported test metadata that is written into a file.

    """
    def __init__(self, test):
        super(ExportedFile, self).__init__()
        self.__file_contents = []
        self.__file_name = None
        self.__test = test
        
    def get_test_object(self):
        """
        Get the test object.
        
        Return value:
        Test-based object.
        
        """
        return self.__test

    def set_file_name(self, name):
        """
        Set the name of the file to output to.

        Keyword arguments:
        name - Name of the output file.

        """
        self.__file_name = name

    def add_line(self, line, auto_newline = True):
        """
        Add a line to the file contents.

        Keyword arguments:
        line - Line to add to the file contents.
        auto_newline - If True automatically add a newline to the end of the.
                       line.

        """
        if auto_newline:
            line = "{line}\n".format(line = line)
        self.__file_contents.append(line)

    def write(self, simulated = False):
        """
        Write out the exported file.

        Keyword arguments:
        simulated - If True then the file contents will be logged, but the file
                    will not actually be written.

        """
        if self.__file_name is None:
            raise Exception("Unable to export to file since the file name has not been set")
        if simulated:
            self.get_logger().debug("Simulating writing file '{file_name}':\n{file_contents}".format(file_name = self.__file_name, file_contents = ''.join(self.__file_contents)))
        else:
            self.get_logger().debug("Writing file '{file_name}':\n{file_contents}".format(file_name = self.__file_name, file_contents = ''.join(self.__file_contents)))
            file_object = open(self.__file_name, 'w')
            file_object.writelines(self.__file_contents)
            file_object.close()

