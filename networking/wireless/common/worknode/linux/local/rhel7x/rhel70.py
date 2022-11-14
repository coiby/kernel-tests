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
The worknode.linux.local.rhel7x.rhel70 module provides a class
(LocalRHEL70WorkNode) that represents a local Red Hat Enterprise Linux 7.0
machine.

"""

__author__ = 'Ken Benoit'

import worknode.linux.local.rhel7

class LocalRHEL70WorkNode(worknode.linux.local.rhel7.LocalRHEL7WorkNode):
    """
    LocalRHEL70WorkNode represents a local Red Hat Enterprise Linux 7.0 machine.

    """
    def __init__(self):
        super(LocalRHEL70WorkNode, self).__init__()
        self._set_minor_version(version_number = 0)
        self.__configure_component_managers()

    def __configure_component_managers(self):
        self._add_component_manager(
            component_name = 'network',
            manager_class = 'NetworkManager',
            manager_module = 'worknode.linux.manager.rhel7.minor_versions.rhel70.network',
        )
