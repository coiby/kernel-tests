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
The functional.crda.regdom_verify module provides a class (Test) that provides
details on how to run the test.

"""

__author__ = 'Ken Benoit'

import base.test
from base.exception.test import *
import worknode.worknode_factory
import re

class Test(base.test.Test):
    def __init__(self):
        super(Test, self).__init__()
        self.set_test_name(name = '/kernel/wireless_tests/functional/crda/regdom_verify')
        self.set_test_author(name = 'Ken Benoit', email = 'kbenoit@redhat.com')
        self.set_test_description(description = 'Verify the regulatory domain rules')

        self.__db_entries = {}

        self.add_test_step(
            test_step = self.get_work_node,
        )
        self.add_test_step(
            test_step = self.determine_crda_version,
            test_step_description = 'Determine what version of crda is installed',
        )
        self.add_test_step(
            test_step = self.set_reg_domain,
            test_step_description = 'Set the system to a random regulatory domain',
        )
        self.add_test_step(
            test_step = self.verify_regdom_rules,
            test_step_description = 'Verify that the regulatory domain rules are correct',
        )

    def get_work_node(self):
        """
        Generate a work node object to use for the test.

        """
        self.work_node = worknode.worknode_factory.WorkNodeFactory().get_work_node()

    def determine_crda_version(self):
        """
        Determine what version of crda is installed.

        """
        crda_version = None
        output = self.work_node.run_command("rpm -qi crda")
        for line in output:
            if re.search("Version\s+:", line):
                match = re.search("Version\s+: (?P<version>\S+)", line)
                crda_version = match.group("version")
                break
        self.get_logger().info(
            "Testing crda-{version}".format(version = crda_version)
        )
        self.__parse_db_file(
            file_name = "dbs/{crda_version}.txt".format(
                crda_version = crda_version
            )
        )

    def set_reg_domain(self):
        """
        Set the system to a random regulatory domain to test against.

        """
        random = self.get_random_module()
        region = random.choice(list(self.__db_entries.keys()))
        self.work_node.run_command("iw reg set {0}".format(region))

    def verify_regdom_rules(self):
        """
        Check the current global regulatory domain rules against what the
        database says.

        """
        region = None
        ranges = None
        output = self.work_node.run_command("iw reg get")
        for line in output:
            if re.search("phy#", line):
                # We only want to check against the regulatory rules on the
                # system, not on the physical card (since many cards are
                # "self-managed" now and therefore don't use the crda rules)
                break
            if re.search("country", line):
                match = re.search("country (?P<region>\S{2})", line)
                region = match.group("region")
                ranges = self.__db_entries[region]
            if region is None:
                continue
            match = re.search("\((?P<start>\d+)\s+-\s+(?P<end>\d+)\s+@\s+(?P<width>\d+)\),\s+\(.*?(?P<output_restriction>\d+).*?\)(?P<options>.*)", line)

            if match:
                range_dict = {
                    "start": match.group("start"),
                    "end": match.group("end"),
                    "width": match.group("width"),
                    "output_restriction": match.group("output_restriction"),
                }
                if range_dict in ranges:
                    ranges.remove(range_dict)
                else:
                    raise TestFailure(
                        "Rule '{0}' from iw reg get does not appear in the database".format(
                            line
                        )
                    )
        if len(ranges) != 0:
            raise TestFailure(
                "Mismatch in the number of rules between iw reg get and the database"
            )

    def __parse_db_file(self, file_name):
        file_data = None
        with open(file_name) as db_file:
            file_data = db_file.readlines()

        region = None
        for line in file_data:
            if line.find("#"):
                line = line.rstrip("#")
            if re.search("^country", line):
                match =  re.search("^country (?P<region>\S{2})", line)
                region = match.group("region")
                self.__db_entries[region] = []
            elif region is not None:
                match = re.search("\((?P<start>\d+)\s+-\s+(?P<end>\d+)\s+@\s+(?P<width>\d+)\),\s+\(.*?(?P<output_restriction>\d+).*?\)", line)
                if not match:
                    continue
                range_dict = {
                    "start": match.group("start"),
                    "end": match.group("end"),
                    "width": match.group("width"),
                    "output_restriction": match.group("output_restriction"),
                }
                self.__db_entries[region].append(range_dict)

if __name__ == '__main__':
    exit(Test().run_test())
