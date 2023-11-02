# Copyright (c) 2023 Red Hat, Inc. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

from drgn import NULL, Object, cast, container_of, execscript, offsetof, reinterpret, sizeof
from drgn.helpers.common import *
from drgn.helpers.linux import *

# Print jiffies address
print('[system jiffies info]:')   
print(prog['jiffies'].address_of_())

# Print linux_banner value      
print('\n[linux banner]:')                                                                                                                                                                                                            
print(prog['linux_banner'])
# Print linux_banner value in bytes
print(prog['linux_banner'].to_bytes_())

# Print all pids of tasks
print('\n[first tasks info]:') 
num_tasks=10
for task in for_each_task(prog):
    num_tasks -= 1
    if num_tasks < 0:
        break
    print(task.pid, task.parent.pid, task_cpu(task), 
          task_state_to_char(task), task.comm.string_().decode())

# Print stack trace of systemd task
name_of_task = 'systemd'
print('\n[stack trace of {}]:'.format(name_of_task))
for task in for_each_task(prog):
   if task.comm.string_().decode() == name_of_task:
       print(prog.stack_trace(task))
       print('----')
       print_annotated_stack(prog.stack_trace(task))
       print('\n--------\n')
