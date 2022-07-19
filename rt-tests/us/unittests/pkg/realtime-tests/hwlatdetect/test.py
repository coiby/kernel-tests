#!/usr/bin/python3
"""
Unittest for hwlatdetect of realtime-tests
"""
import os
import rtut

class HwlatdetectTest(rtut.RTUnitTest):

    def setUp(self):
        self.tmp_file = f"{os.getcwd()}/report.txt"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help(self):
        self.run_cmd('hwlatdetect --help')

    def test_long(self):
        self.run_cmd('hwlatdetect --duration 10s --threshold 10000 --hardlimit 10000 '
                     f'--window 1000000 --width 500000 --report {self.tmp_file} --debug')

    def test_quiet(self):
        self.run_cmd('hwlatdetect --duration 10s --quiet')

    def test_watch(self):
        self.run_cmd('hwlatdetect --duration 10s --watch')

if __name__ == '__main__':
    HwlatdetectTest.run_unittests()
