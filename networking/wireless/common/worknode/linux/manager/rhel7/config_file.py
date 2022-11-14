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
The worknode.linux.manager.rhel6.config_file module provides a class
(ConfigFileManager) that manages the config files present on the work node.

"""

__author__ = 'Ken Benoit'

import worknode.linux.manager.config_file_base
import worknode.linux.manager.rhel7.file.wpa_supplicant_conf
import worknode.linux.manager.rhel7.file.wpa_supplicant_sysconfig

class ConfigFileManager(worknode.linux.manager.config_file_base.ConfigFileManager):
    """
    ConfigFileManager is an object that manages the config files present on the
    work node. It acts as a container for accessing the config files.

    """
    def __init__(self, parent):
        super(ConfigFileManager, self).__init__(parent = parent)
        self.__configure_config_file_objects()

    def __configure_config_file_objects(self):
        self.__configure_wpa_supplicant_conf()
        self.__configure_wpa_supplicant_sysconfig()

    def __configure_wpa_supplicant_conf(self):
        wpa_supplicant_conf = worknode.linux.manager.rhel7.file.wpa_supplicant_conf.WpaSupplicantConf(
            work_node = self._get_work_node(),
        )
        self._add_config_file_object(
            config_file_name = 'wpa_supplicant.conf',
            config_file_object = wpa_supplicant_conf,
        )

    def __configure_wpa_supplicant_sysconfig(self):
        wpa_supplicant_sysconfig = worknode.linux.manager.rhel7.file.wpa_supplicant_sysconfig.WpaSupplicantSysconfig(
            work_node = self._get_work_node(),
        )
        self._add_config_file_object(
            config_file_name = 'wpa_supplicant',
            config_file_object = wpa_supplicant_sysconfig,
        )
