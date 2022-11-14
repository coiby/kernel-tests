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
The worknode.linux.manager.file_system_base module provides a class
(FileSystemManager) that manages all file-related activities.

"""

__author__ = 'Ken Benoit'

import worknode.worknode_component_manager
import framework
from worknode.exception.worknode_executable import *

class FileSystemManager(worknode.worknode_component_manager.WorkNodeComponentManager):
    """
    FileSystemManager is an object that manages all file-related activities. It
    acts as a container for file-related commands as well as being a unified
    place to request abstracted file information from.

    """
    def __init__(self, parent):
        super(FileSystemManager, self).__init__(parent = parent)

    def create_directory(self, directory_path):
        """
        Abstract: Create a directory and return its object.

        Keyword arguments:
        directory_path - Path of the directory to create.

        Return value:
        Object representing the directory.

        """
        raise NotImplementedError

    def get_directory(self, directory_path):
        """
        Abstract: Get an object that represents the directory requested.

        Keyword arguments:
        directory_path - Path to the requested directory.

        Return value:
        Object representing the directory.

        """
        raise NotImplementedError

    def delete_directory(self, directory_path):
        """
        Delete a directory given the directory path.

        Keyword arguments:
        directory_path - Path to the directory to be deleted.

        """
        self.get_directory(directory_path = directory_path).delete()

    def get_file(self, file_path):
        """
        Abstract: Get an object that represents the file requested.

        Keyword arguments:
        file_path - Path to the requested file.

        Return value:
        Object representing the file.

        """
        raise NotImplementedError

    def delete_file(self, file_path):
        """
        Delete a file given the file path.

        Keyword arguments:
        file_path - Path to the file to be deleted.

        """
        self.get_file(file_path = file_path).delete()

class DirectoryObject(framework.Framework):
    """
    DirectoryObject is an object that represents a file system directory.

    """
    def __init__(self, parent, path):
        super(DirectoryObject, self).__init__()
        self.__parent = parent
        self.__path = path

    def delete(self):
        """
        Abstract: Delete the directory from the work node.

        """
        raise NotImplementedError

    def _get_parent(self):
        return self.__parent

    def _get_path(self):
        return self.__path

    def _get_work_node(self):
        return self._get_parent()._get_work_node()

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent}, path = "{path}")'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
            path = self._get_path(),
        )

    def __str__(self):
        return self._get_path()

class FileObject(framework.Framework):
    """
    FileObject is an object that represents a file system file.

    """
    def __init__(self, parent, path):
        super(FileObject, self).__init__()
        self.__parent = parent
        self.__path = path

    def delete(self):
        """
        Abstract: Delete the file from the work node.

        """
        raise NotImplementedError

    def verify_checksum(self, checksum_type, verification_checksum):
        """
        Abstract: Compares the provided checksum against the generated checksum
        for the file.

        Keyword arguments:
        checksum_type - Type of checksum being provided.
        verification_checksum - Checksum string to compare the generated
                                checksum against.

        """
        raise NotImplementedError

    def read_file(self):
        """
        Abstract: Read out the contents of the file.

        Return value:
        List of file contents.

        """
        raise NotImplementedError

    def _get_parent(self):
        return self.__parent

    def _get_path(self):
        return self.__path

    def _get_work_node(self):
        return self._get_parent()._get_work_node()

    def __repr__(self):
        return '{module}.{class_name}(parent = {parent}, path = "{path}")'.format(
            module = self.__module__,
            class_name = self.__class__.__name__,
            parent = self._get_parent(),
            path = self._get_path(),
        )

    def __str__(self):
        return self._get_path()
