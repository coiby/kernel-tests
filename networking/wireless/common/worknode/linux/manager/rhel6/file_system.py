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
The worknode.linux.manager.rhel6.file_system module provides a class
(FileSystemManager) that manages all file-related activities.

"""

__author__ = 'Ken Benoit'

import re

import worknode.linux.manager.file_system_base
from worknode.exception.worknode_executable import *
from worknode.linux.manager.exception.file_system import *

class FileSystemManager(worknode.linux.manager.file_system_base.FileSystemManager):
    """
    FileSystemManager is an object that manages all file-related activities. It
    acts as a container for file-related commands as well as being a unified
    place to request abstracted file information from.

    """
    def __init__(self, parent):
        super(FileSystemManager, self).__init__(parent = parent)

    def create_directory(self, directory_path):
        """
        Create a directory and return its object.

        Keyword arguments:
        directory_path - Path of the directory to create.

        Return value:
        Object representing the directory.

        """
        work_node = self._get_work_node()
        work_node.run_command(command = 'mkdir -p {0}'.format(directory_path))
        return self.get_directory(directory_path = directory_path)

    def get_directory(self, directory_path):
        """
        Get an object that represents the directory requested.

        Keyword arguments:
        directory_path - Path to the requested directory.

        Return value:
        Object representing the directory.

        """
        work_node = self._get_work_node()
        output = work_node.run_command(
            command = 'ORIGDIR=$PWD; cd {0}; echo $PWD; cd $ORIGDIR'.format(
                directory_path
            ),
        )
        directory_path = output[0].strip()
        output = work_node.run_command(
            command = 'if [ -d {0} ]; then echo 1; else echo 0; fi'.format(
                directory_path,
            ),
        )
        if output[0].strip() == '0':
            raise DirectoryException(
                "'{0}' is not a directory".format(directory_path)
            )
        return worknode.linux.manager.rhel6.file_system.DirectoryObject(
            parent = self,
            path = directory_path,
        )

    def get_file(self, file_path):
        """
        Get an object that represents the file requested.

        Keyword arguments:
        file_path - Path to the requested file.

        Return value:
        Object representing the file.

        """
        work_node = self._get_work_node()
        output = work_node.run_command(
            command = 'ORIGDIR=$PWD; cd $(dirname {0}); echo $PWD/$(basename {0}); cd $ORIGDIR'.format(
                file_path
            ),
        )
        file_path = output[0].strip()
        output = work_node.run_command(
            command = 'if [ -f {0} ]; then echo 1; else echo 0; fi'.format(
                file_path
            ),
        )
        if output[0].strip() == '0':
            raise FileException(
                "'{0}' is not a file".format(file_path)
            )
        return worknode.linux.manager.rhel6.file_system.FileObject(
            parent = self,
            path = file_path,
        )

class DirectoryObject(worknode.linux.manager.file_system_base.DirectoryObject):
    """
    DirectoryObject is an object that represents a file system directory.

    """
    def __init__(self, parent, path):
        super(DirectoryObject, self).__init__(parent = parent, path = path)

    def delete(self):
        """
        Delete the directory from the file system.

        """
        work_node = self._get_work_node()
        output = work_node.run_command(
            command = 'rmdir {0}'.format(self._get_path()),
        )
        if re.search('failed to remove', ''.join(output)):
            raise FailedCommandOutputError(
                "Failed to remove {path}: {output}".format(
                    path = self._get_path(),
                    output = ''.join(output),
                ),
            )

class FileObject(worknode.linux.manager.file_system_base.FileObject):
    """
    FileObject is an object that represents a file system file.

    """
    def __init__(self, parent, path):
        super(FileObject, self).__init__(parent = parent, path = path)

    def verify_checksum(self, checksum_type, verification_checksum):
        """
        Compares the provided checksum against the generated checksum for the
        file.

        Keyword arguments:
        checksum_type - Type of checksum being provided (e.g. "sha1", "md5",
                        etc.).
        verification_checksum - Checksum string to compare the generated
                                checksum against.

        """
        command = None
        if checksum_type == 'sha1':
            command = 'sha1sum {0}'.format(self._get_path())
        elif checksum_type == 'md5':
            command = 'md5sum {0}'.format(self._get_path())
        else:
            raise ChecksumException(
                "Unknown checksum type '{0}' provided".format(checksum_type)
            )
        work_node = self._get_work_node()
        output = work_node.run_command(command = command)
        generated_match = re.search(
            '^(?P<generated_checksum>\S+)\s+',
            output[0]
        )
        generated_checksum = generated_match.group('generated_checksum')
        verification_match = re.search(
            '^(?P<verification_checksum>\S+)\s+',
            verification_checksum,
        )
        verification_checksum = verification_match.group(
            'verification_checksum'
        )
        if verification_checksum != generated_checksum:
            raise ChecksumException(
                "Verification checksum did not match the generated checksum"
            )

    def read_file(self):
        """
        Read out the contents of the file.

        Return value:
        List of file contents.

        """
        work_node = self._get_work_node()
        output = work_node.run_command(
            command = 'cat {0}'.format(self._get_path()),
        )
        return output

    def delete(self):
        """
        Delete the file from the file system.

        """
        work_node = self._get_work_node()
        output = work_node.run_command(
            command = 'rm {0}'.format(self._get_path()),
        )
        if re.search('cannot remove', ''.join(output)):
            raise FailedCommandOutputError(
                "Failed to remove {path}: {output}".format(
                    path = self._get_path(),
                    output = ''.join(output),
                ),
            )
