#!/usr/bin/python
# Copyright (c) 2019 Red Hat, Inc. All rights reserved. This copyrighted material
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
The worknode.linux.manager.rhel8.power module provides a class
(PowerManager) that manages all power management-related activities.

"""

__author__ = 'Ken Benoit'

import worknode.linux.manager.power_base
from worknode.exception.worknode_executable import *
from worknode.linux.manager.exception.file_system import *

class PowerManager(worknode.linux.manager.power_base.PowerManager):
    """
    PowerManager is an object that manages all power management-related
    activities.

    """
    def __init__(self, parent):
        super(PowerManager, self).__init__(parent = parent)

    def suspend(self, seconds):
        """
        Suspend the system for the provided number of seconds.

        Keyword arguments:
        seconds - Number of seconds to suspend the system for before
                  automatically resuming.

        """
        if type(seconds) is not int:
            raise TypeError("seconds needs to be int")
        work_node = self._get_work_node()
        work_node.run_command(command = 'echo "0" > /sys/class/rtc/rtc0/wakealarm')
        work_node.run_command(command = 'echo "+{0}" > /sys/class/rtc/rtc0/wakealarm'.format(str(seconds)))
        work_node.run_command(command = 'systemctl suspend')
