#!/usr/bin/python3
"""
Unittest for oslat of realtime-tests
"""
import os
import rtut

class OslatTest(rtut.RTUnitTest):

    def setUp(self):
        self.tmp_file = f"{os.getcwd()}/output.json"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help(self):
        self.run_cmd('oslat -h')

    def test_version(self):
        self.run_cmd('oslat -v')

    def test_long(self):
        self.run_cmd('oslat --bucket-size 64 --bias --cpu-list 1,2 --cpu-main-thread '
                     f'--duration 10s --json={self.tmp_file} --rtprio 50 --workload-mem 4K '
                     '--quiet --single-preheat --trace-threshold 10000000 '
                     '--workload no --zero-omit')

    def test_short(self):
        self.run_cmd('oslat -b 64 -B -c 1,2 -C -D 10s -f 50 -m 4K -q -s -T 10000000 -w no -z')

if __name__ == '__main__':
    OslatTest.run_unittests()
