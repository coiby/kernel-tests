#!/usr/bin/python
# Copyright (c) 2018 Red Hat, Inc. All rights reserved. This copyrighted material
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
The worknode.linux.manager.rhel8.file.wpa_supplicant module provides a class
(ConfigFileManager) that manages the config files present on the work node.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.file.wpa_supplicant_sysconfig

class WpaSupplicantSysconfig(worknode.linux.file.wpa_supplicant_sysconfig.WpaSupplicantSysconfig):
    """
    WpaSupplicantSysconfig represents the sysconfig wpa_supplicant config file
    and the methods of reading and writing the file.

    """
    def __init__(self, work_node):
        super(WpaSupplicantSysconfig, self).__init__(work_node = work_node)
        self._set_file_path(file_path = '/etc/sysconfig/wpa_supplicant')
        self._set_reader(reader = _reader)
        self._set_writer(writer = _writer)
        self.__properties['INTERFACES'] = []
        self.__properties['DRIVERS'] = []
        self.__properties['OTHER_ARGS'] = {}

    def add_interface(self, interface_name):
        self.__properties['INTERFACES'].append(interface_name)

    def add_driver(self, driver_name):
        self.__properties['DRIVERS'].append(driver_name)

    def set_log_file_path(self, log_file_path):
        self.__properties['OTHER_ARGS']['-f'] = log_file_path

    def set_pid_file_path(self, pid_file_path):
        self.__properties['OTHER_ARGS']['-P'] = pid_file_path

    def enable_timestamps(self):
        self.__properties['OTHER_ARGS']['-t'] = None

    def set_debug_level(self, debug_level):
        self.__properties['OTHER_ARGS']['-d'] = str(debug_level)

def _reader(file_contents):
    raise NotImplementedError("Code still in development")
    properties = {}
    properties['INTERFACES'] = []
    properties['DRIVERS'] = []
    properties['OTHER_ARGS'] = {}
    for line in file_contents:
        if re.search('INTERFACES=".*?"', line):
            match = re.search('INTERFACES="(?P<interfaces>.*?)"', line)
            interfaces_string = match.group('interfaces')
            interfaces = interfaces_string.split(' ')
            for interface in interfaces:
                match = re.search('-i(?P<interface_name>\S+)', interface)
                properties['INTERFACES'].append(match.group('interface_name'))
        elif re.search('DRIVERS=".*?"', line):
            match = re.search('DRIVERS="(?P<drivers>.*?)"', line)
            drivers_string = match.group('drivers')
            drivers = drivers_string.split(' ')
            for driver in drivers:
                match = re.search('-D(?P<driver_name>\S+)', driver)
                properties['DRIVERS'].append(match.group('driver_name'))
        elif re.search('OTHER_ARGS=".*?"', line):
            match = re.search('OTHER_ARGS="(?P<args>.*?)"', line)
            other_args_string = match.group('args')
            other_args = other_args_string.split(' ')
            for arg in other_args:
                match = re.search('(?P<flag>-\w)', arg)


    return properties

def _writer(properties):
    lines = []
    if 'INTERFACES' in properties:
        interfaces = []
        for interface in properties['INTERFACES']:
            interfaces.append('-i{0}'.format(interface))
        lines.append('INTERFACES="{0}"\n'.format(' '.join(interfaces)))
    if 'DRIVERS' in properties:
        drivers = []
        for driver in properties['DRIVERS']:
            drivers.append('-D{0}'.format(driver))
        lines.append('DRIVERS="{0}"\n'.format(' '.join(drivers)))
    if 'OTHER_ARGS' in properties:
        other_args = []
        for (key, value) in properties['OTHER_ARGS'].items():
            other_args.append(key)
            if value is not None:
                other_args.append(value)
        lines.append('OTHER_ARGS="{0}"\n'.format(' '.join(other_args)))
    return lines
