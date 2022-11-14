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
The exported_file_factory module provides a way for automatically generating an
exported file object of the proper type.

"""

__author__ = 'Ken Benoit'

import framework
from base.exported_file_formats import *

class ExportedFileFactory(framework.Framework):
    """
    ExportedFileFactory provides a method to automatically generate an exported
    file object of the proper type.

    """
    def get_exported_file(self, file_format, test):
        """
        Get a exported file object to interact with.

        Return value:
        base.exported_file-based object.

        """
        format_dictionary = {
                'PURPOSE': purpose.Purpose,
                'custom': custom.Custom,
            }

        exported_file_class = None
        
        try:
            exported_file_class = format_dictionary[file_format]
        except KeyError:
            raise RuntimeError("Unable to locate a suitable export object for file format: {0}".format(file_format))
        except Exception as e:
            raise e

        return exported_file_class(test = test)

