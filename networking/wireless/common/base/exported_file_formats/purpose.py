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
The purpose module provides a class (Purpose) that represents a PURPOSE file
with test details.

"""

__author__ = 'Ken Benoit'

import base.exported_file

class Purpose(base.exported_file.ExportedFile):
    """
    Purpose represents a PURPOSE file with test details.

    """
    def __init__(self, test):
        super(Purpose, self).__init__(test = test)
        test = self.get_test_object()
        self.set_file_name(name = 'PURPOSE')
        if test.get_test_name() is not None:
            self.add_line(line = "PURPOSE of {0}".format(test.get_test_name()))
        if test.get_test_description() is not None:
            self.add_line(line = "Description: {0}".format(test.get_test_description()))
        if test.get_test_author() is not None:
            author_line = "Author: {0}".format(test.get_test_author())
            if test.get_test_author_email() is not None:
                author_line += " <{0}>".format(test.get_test_author_email())
            self.add_line(line = author_line)
        self.add_line(line = "Test steps:")
        for step_number in range(0, test.get_test_step_list().get_number_of_test_steps()):
            description = test.get_test_step_list().get_test_step_description(step_number = step_number)
            if description is not None:
                self.add_line(line = " * {0}".format(description))


