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
The worknode.linux.file.config_file_base module provides a base class
(ConfigFileBase) that all system config files should inherit from.

"""

__author__ = 'Ken Benoit'

import framework
import random
import os
import shutil

class ConfigFileBase(framework.Framework):
    """
    ConfigFileBase represents a base class for all system config files.

    """
    def __init__(self, work_node):
        super(ConfigFileBase, self).__init__()
        self.__work_node = work_node
        self.__file_path = None
        self.__reader = None
        self.__writer = None
        self.__properties = None
        self.__backups = []

    def __get_file_directory(self):
        file_path = self._get_file_path()
        file_path_parts = file_path.split('/')
        file_directory = ''
        for file_path_parts_index in range(0, len(file_path_parts) - 1):
            file_directory += file_path_parts[file_path_parts_index] + '/'
        return file_directory

    def _set_file_path(self, file_path):
        self.__file_path = file_path

    def _get_file_path(self):
        if self.__file_path is None:
            raise NameError("file path has not been defined")
        return self.__file_path

    def _set_reader(self, reader):
        self.__reader = reader

    def _get_reader(self):
        if self.__reader is None:
            raise NameError("file reader has not been defined")
        return self.__reader

    def _set_writer(self, writer):
        self.__writer = writer

    def _get_writer(self):
        if self.__writer is None:
            raise NameError("file writer has not been defined")
        return self.__writer

    def get_file_contents_properties(self):
        """
        Get the properties dictionary from the file contents from the read file.

        Return value:
        Dictionary of the file contents properties.

        """
        if self.__properties is None:
            raise NameError("file contents properties have not been set yet")
        return self.__properties

    def set_file_contents_properties(self, properties):
        """
        Set the properties dictionary to write out to the file.

        Keyword arguments:
        properties - Dictionary containing the properties to write out to the
                     file.

        """
        self.__properties = properties

    def backup_file(self, backup_name = None):
        """
        Backup the file.

        Keyword arguments:
        backup_name - Name to use for the backup.

        """
        file_path = self._get_file_path()
        if backup_name is None:
            backup_name = self.__get_file_directory() + "temp{0:09d}.tmp".format(
                random.randint(1, 999999999)
            )
        self.get_logger().debug(
            "Backing up {orig_file} to {backup_file}".format(
                orig_file = file_path,
                backup_file = backup_name,
            )
        )
        shutil.copy(file_path, backup_name)
        self.__backups.append(backup_name)

    def restore_file(self, backup_name = None):
        """
        Restore the file from the latest backup and delete the backup.

        Keyword arguments:
        backup_name - Name of the backup file to restore from.

        """
        file_path = self._get_file_path()
        latest_backup = None
        if backup_name is None:
            try:
                latest_backup = self.__backups.pop()
            except IndexError:
                raise Exception("There are no file backups to restore from")
        else:
            latest_backup = backup_name
            if backup_name in self.__backups:
                self.__backups.remove(backup_name)
        self.get_logger().debug(
            "Restoring {orig_file} from backup {backup_file}".format(
                orig_file = file_path,
                backup_file = latest_backup,
            )
        )
        os.rename(latest_backup, file_path)

    def read(self):
        """
        Open and read back the contents of the file, closing the file once
        complete.

        """
        file_path = self._get_file_path()
        self.get_logger().debug("Reading file {0}".format(file_path))
        file_object = open(file_path, 'r')
        lines = file_object.readlines()
        file_object.close()
        self.__properties = self._get_reader()(file_contents = lines)

    def write(self):
        """
        Open and write the properties to the file, closing the file once
        complete.

        """
        file_path = self._get_file_path()
        self.get_logger().debug("Writing file {0}".format(file_path))
        lines = self._get_writer()(properties = self._get_properties())
        file_contents = ''
        for line in lines:
            file_contents += line
        self.get_logger().debug("File contents:\n{0}".format(file_contents))
        file_object = open(file_path, 'w')
        file_object.writelines(lines)
        file_object.close()
