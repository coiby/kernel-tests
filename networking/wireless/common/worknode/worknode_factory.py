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
The worknode_factory module provides a way for automatically generating a work
node object of the proper type for the OS it is being instantiated for.

"""

__author__ = 'Ken Benoit'

from subprocess import Popen, PIPE
import re
import sys

import framework

class WorkNodeFactory(framework.Framework):
    """
    WorkNodeFactory provides a method to automatically generate a work node
    object of the proper type for the OS it is being instantiated for.

    """
    def get_work_node(self):
        """
        Get a work node object to interact with.

        Return value:
        worknode.base.WorkNodeBase-based object that is specific for the OS of
        the work node it is being instantiated for.

        """
        os_dictionary_local = {
            'Red Hat Enterprise Linux': {
                6: {
                    'module': 'worknode.linux.local.rhel6',
                    'class': 'LocalRHEL6WorkNode',
                },
                7: {
                    0: {
                        'module': 'worknode.linux.local.rhel7x.rhel70',
                        'class': 'LocalRHEL70WorkNode',
                    },
                    1: {
                        'module': 'worknode.linux.local.rhel7x.rhel71',
                        'class': 'LocalRHEL71WorkNode',
                    },
                },
                8: {
                    'module': 'worknode.linux.local.rhel8',
                    'class': 'LocalRHEL8WorkNode',
                },
            },
            'Fedora': {
                20: {
                    'module': 'worknode.linux.local.fedora20',
                    'class': 'LocalFedora20WorkNode',
                },
            },
            'CentOS Linux': {
                6: {
                    'module': 'worknode.linux.local.rhel6',
                    'class': 'LocalRHEL6WorkNode',
                },
                7: {
                    0: {
                        'module': 'worknode.linux.local.rhel7x.rhel70',
                        'class': 'LocalRHEL70WorkNode',
                    },
                    1: {
                        'module': 'worknode.linux.local.rhel7x.rhel71',
                        'class': 'LocalRHEL71WorkNode',
                    },
                },
                8: {
                    'module': 'worknode.linux.local.rhel8',
                    'class': 'LocalRHEL8WorkNode',
                },
            },
            'CentOS Stream': {
                6: {
                    'module': 'worknode.linux.local.rhel6',
                    'class': 'LocalRHEL6WorkNode',
                },
                7: {
                    0: {
                        'module': 'worknode.linux.local.rhel7x.rhel70',
                        'class': 'LocalRHEL70WorkNode',
                    },
                    1: {
                        'module': 'worknode.linux.local.rhel7x.rhel71',
                        'class': 'LocalRHEL71WorkNode',
                    },
                },
                8: {
                    'module': 'worknode.linux.local.rhel8',
                    'class': 'LocalRHEL8WorkNode',
                },
            },
        }
        release_regexes = ['(?P<os_name>.+?)\s+release\s+(?P<major_version>\d+)\.?(?P<minor_version>\d*)']
        commands_to_try = ['cat /etc/redhat-release', 'cat /etc/issue']

        command_output = ''

        work_node_class = None
        work_node_module = None

        for command in commands_to_try:
            process = Popen(command, shell = True, stdout = PIPE)
            process.wait()
            output = process.stdout.readlines()
            command_output = ''
            for line in output:
                if type(line) is not str:
                    line = line.decode("utf-8")
                command_output += line
            # Go through the lines of output
            for line in output:
                if type(line) is not str:
                    line = line.decode("utf-8")
                # Loop through the release regular expressions to try
                for release_regex in release_regexes:
                    # See if we get a match from this particular regex to match
                    # against a release string
                    match = re.search(release_regex, line)
                    if match:
                        for os_name in os_dictionary_local.keys():
                            # Check to see if we got a match on the OS name
                            if re.search(os_name, match.group('os_name')):
                                match = re.search(release_regex, line)
                                full_os_name = match.group('os_name')
                                major_version = int(match.group('major_version'))
                                minor_version = 0
                                if match.group('minor_version') != '':
                                    minor_version = int(match.group('minor_version'))
                                os_versions = os_dictionary_local[os_name]
                                # If os_versions is a dictionary then it has
                                # some major version numbers associated with it
                                if type(os_versions) is dict and 'module' not in os_versions:
                                    # Check to see if our specific major version
                                    # number has an entry
                                    if major_version in os_versions:
                                        os_versions_major = os_versions[major_version]
                                        # If os_versions_major is a dictionary
                                        # then it has some minor version numbers
                                        # associated with it
                                        if type(os_versions_major) is dict and 'module' not in os_versions_major:
                                            # Check to see if our specific minor
                                            # version number has an entry
                                            if minor_version in os_versions_major:
                                                work_node_class = os_versions_major[minor_version]['class']
                                                work_node_module = os_versions_major[minor_version]['module']
                                                break
                                            # If we can't find our specific
                                            # minor version then take the work
                                            # node class for the most recent
                                            # minor version
                                            else:
                                                minor_versions = list(os_versions_major.keys())
                                                minor_versions.sort()
                                                latest_minor = minor_versions[-1]
                                                work_node_class = os_versions_major[latest_minor]['class']
                                                work_node_module = os_versions_major[latest_minor]['module']
                                                break
                                        else:
                                            work_node_class = os_versions_major['class']
                                            work_node_module = os_versions_major['module']
                                            break
                                    # If we can't find our specific major
                                    # version then take the work node class for
                                    # the most recent major version
                                    else:
                                        major_versions = list(os_versions.keys())
                                        major_versions.sort()
                                        latest_major = major_versions[-1]
                                        work_node_class = os_versions[latest_major]['class']
                                        work_node_module = os_versions[latest_major]['module']
                                        break
                            if work_node_class is not None:
                                break
                    if work_node_class is not None:
                        break
                if work_node_class is not None:
                    break
            if work_node_class is not None:
                break

        if not work_node_class:
            raise RuntimeError("Unable to locate a suitable work node class for the platform: {0}".format(command_output))

        # Dynamically import the proper work node module
        try:
            # Use importlib if possible (preferred method for Python3)
            import importlib
            module = importlib.import_module(work_node_module)
            return getattr(module, work_node_class)()
        except ImportError:
            # If importlib is not available then this method will work in a
            # pinch
            map(__import__, [work_node_module])
            # Return an instantiation of the work node class
            return getattr(sys.modules[work_node_module], work_node_class)()
