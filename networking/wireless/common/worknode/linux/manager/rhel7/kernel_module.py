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
The worknode.linux.manager.rhel7.kernel_module module provides a class
(KernelModuleManager) that manages all kernel module-related activities.

"""

__author__ = 'Ken Benoit'

import worknode.linux.manager.kernel_module_base
import framework
import worknode.linux.util.lsmod
import worknode.linux.util.modprobe

class KernelModuleManager(worknode.linux.manager.kernel_module_base.KernelModuleManager):
    """
    KernelModuleManager is an object that manages all kernel module-related
    activities. It acts as a container for kernel module-related commands as
    well as being a unified place to request abstracted kernel module
    information from.

    """
    def __init__(self, parent):
        super(KernelModuleManager, self).__init__(parent = parent)
        self.__configure_executables()

    def __configure_executables(self):
        # Configure lsmod
        lsmod = self.add_command(
            command_name = 'lsmod',
            command_object = worknode.linux.util.lsmod.lsmod(
                work_node = self._get_work_node(),
            ),
        )
        lsmod_parser = lsmod.initialize_command_parser(output_type = 'table')
        lsmod_parser.set_column_titles(
            titles = ['module', 'size', 'used_by_counter', 'used_by_modules'],
        )
        lsmod_parser.add_regular_expression(
            regex = '(?P<module>\S+)\s+(?P<size>\d+)\s+'
                + '(?P<used_by_counter>\d+)\s+(?P<used_by_modules>\S*)',
        )
        # Configure modprobe
        modprobe = self.add_command(
            command_name = 'modprobe',
            command_object = worknode.linux.util.modprobe.modprobe(
                work_node = self._get_work_node(),
            ),
        )
        modprobe.set_failure_regular_expression(regex = 'FATAL')

    def refresh_module_list(self, preferred_command = 'lsmod'):
        """
        Refresh the cached list of kernel module objects.

        Keyword arguments:
        preferred_command - Command to use when listing the kernel modules in
                            use.

        """
        self._clear_cached_modules()
        # If the command to use is lsmod
        if preferred_command == 'lsmod':
            lsmod = self.get_command_object(command_name = 'lsmod')
            parsed_output = lsmod.run_command()
            for row in parsed_output:
                if row['module'] == 'Module' and row['size'] == 'Size':
                    continue
                else:
                    module_name = row['module']
                    module_object = KernelModule(
                        name = module_name,
                        parent = self,
                    )
                    self._add_kernel_module_object(
                        module_object = module_object,
                    )
            for row in parsed_output:
                used_by_modules = row['used_by_modules'].split(',')
                base_module = self.get_kernel_module(
                    module_name = row['module'],
                )
                if used_by_modules[0] == '':
                    continue
                for module_name in used_by_modules:
                    module = self.get_kernel_module(module_name = module_name)
                    base_module._add_module_using_this(module = module)
                    module._add_using_module(module = base_module)
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )

    def insert_kernel_module(self, module_name, preferred_command = 'modprobe'):
        """
        Attempt to insert the indicated kernel module.

        Keyword arguments:
        module_name - Name of the module.
        preferred_command - Command to use when inserting the kernel module.

        Return value:
        Object representing the kernel module being inserted.

        """
        # If the command to use is modprobe
        if preferred_command == 'modprobe':
            modprobe = self.get_command_object(command_name = 'modprobe')
            modprobe.run_command(command_arguments = module_name)
            self.refresh_module_list()
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )

class KernelModule(worknode.linux.manager.kernel_module_base.KernelModule):
    """
    Class that represents a kernel module.

    """
    def __init__(self, name, parent):
        super(KernelModule, self).__init__(name = name, parent = parent)

    def remove(self, smart_remove = True, preferred_command = 'modprobe'):
        """
        Remove the module from the kernel.

        Keyword arguments:
        smart_remove - If True then the modules using this module will be
                       removed before removing this module.
        preferred_command - Command to use when removing the kernel module.

        """
        if smart_remove:
            modules_using_this = self.get_modules_using_this()
            for module in modules_using_this:
                module.remove(
                    smart_remove = True,
                    preferred_command = preferred_command,
                )
        # If the command to use is modprobe
        if preferred_command == 'modprobe':
            modprobe = self._get_kernel_module_manager().get_command_object(
                command_name = 'modprobe',
            )
            modprobe.run_command(
                command_arguments = '-r {0}'.format(self.get_name()),
            )
            self._get_kernel_module_manager()._remove_kernel_module_object(
                module_object = self,
            )
        # We have no idea what command you're trying to use
        else:
            raise CommandNotFoundError(
                "Unable to find a suitable command to use"
            )
