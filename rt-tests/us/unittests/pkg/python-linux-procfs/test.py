#!/usr/bin/python3
"""
Unittest for package python-linux-procfs
"""
import os
import rtut

class PythonLinuxProfsTest(rtut.RTUnitTest):

    def setUp(self):
        self.tmp_file = f"{os.getcwd()}/output.txt"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help_long(self):
        self.run_cmd(f'pflags --help')

    def test_help_short(self):
        self.run_cmd(f'pflags -h')

    def test_pid_all(self):
        self.run_cmd(f'pflags')

    def test_pid_single(self):
        self.run_cmd(f'pflags 1')

    def test_pid_many(self):
        self.run_cmd(f'pflags $(pgrep rcu) $(pgrep systemd)')

if __name__ == '__main__':
    PythonLinuxProfsTest.run_unittests()
