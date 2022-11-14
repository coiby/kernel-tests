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
The worknode.linux.file.wpa_supplicant_sysconfig module provides a class
(WpaSupplicantConf) that represents the wpa_supplicant.conf config file.

"""

__author__ = 'Ken Benoit'

import worknode.linux.file.config_file_base

class WpaSupplicantSysconfig(worknode.linux.file.config_file_base.ConfigFileBase):
    """
    WpaSupplicantSysconfig represents the sysconfig wpa_supplicant config file 
    and the methods of reading and writing the file.

    """
    def __init__(self, work_node):
        super(WpaSupplicantSysconfig, self).__init__(work_node = work_node)
        self.__properties = {}

    def _get_properties(self):
        """
        Get the internally stored properties dictionary.

        """
        return self.__properties

