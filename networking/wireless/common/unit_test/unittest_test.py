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

import base.test
import time

class UnitTestTest(base.test.Test):
    def __init__(self):
        super(UnitTestTest, self).__init__()
        self.add_test_step(
            test_step = self.test_step_0,
            test_step_description = 'Test step 0 description',
            rollback_step = self.rollback_test_step_0,
            rollback_step_description = 'Rollback step 0 description',
        )
        self.add_test_step(
            test_step = self.test_step_1,
            test_step_description = 'Test step 1 description',
            rollback_step = self.rollback_test_step_1,
            rollback_step_description = 'Rollback step 1 description',
        )

    def test_step_0(self):
        self.get_logger().info("Test step 0")

    def test_step_1(self):
        self.get_logger().info("Test step 1")

    def rollback_test_step_0(self):
        self.get_logger().info("Rollback test step 0")

    def rollback_test_step_1(self):
        self.get_logger().info("Rollback test step 1")

if __name__ == '__main__':
    exit(UnitTestTest().run_test())

