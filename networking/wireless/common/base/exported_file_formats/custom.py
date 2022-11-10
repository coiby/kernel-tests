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
The custom module provides a class (Custom) that represents a custom crafted
file with test details.

"""

__author__ = 'Ken Benoit'

import re

import base.exported_file

class Custom(base.exported_file.ExportedFile):
    """
    Custom represents a custom crafted file with test details.

    """
    def __init__(self, test):
        super(Custom, self).__init__(test = test)

        file_object = open('custom_format.template', 'r')
        template_lines = file_object.readlines()
        file_object.close()

        file_name_line = template_lines.pop(0)
        match = re.search('file_name:(?P<file_name>.+)', file_name_line)
        if not match:
            raise Exception("'file_name:' needs to be provided at the beginning of the custom_format.template file")
        self.set_file_name(name = match.group('file_name'))

        test = self.get_test_object()
        for line in template_lines:
            if test.get_test_name() is not None:
                line = line.replace('{test_name}', test.get_test_name())
            else:
                line = line.replace('{test_name}', '')
            if test.get_test_description() is not None:
                line = line.replace('{description}', test.get_test_description())
            else:
                line = line.replace('{description}', '')
            if test.get_test_author() is not None:
                line = line.replace('{author_name}', test.get_test_author())
            else:
                line = line.replace('{author_name}', '')
            if test.get_test_author_email() is not None:
                line = line.replace('{author_email}', test.get_test_author_email())
            else:
                line = line.replace('{author_email}', '')
            if re.search('\{test_step\}', line):
                for step_number in range(len(test.get_test_step_list())):
                    description = test.get_test_step_list().get_test_step_description(step_number = step_number)
                    if description is not None:
                        step_line = line.replace('{test_step}', description)
                        self.add_line(line = step_line, auto_newline = False)
            else:
                self.add_line(line = line, auto_newline = False)

