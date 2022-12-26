#!/usr/bin/python3
"""
Unittest for oslat of realtime-tests
"""
import os
import rtut
import subprocess

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
        self.run_cmd('oslat --bucket-size 64 --bias --cpu-list 1,2 --cpu-main-thread 1 '
                     f'--duration 10s --json={self.tmp_file} --workload-mem 4K '
                     '--single-preheat --trace-threshold 10000000 --workload no --zero-omit')

    def test_rtprio(self):
        self.run_cmd('oslat -z -D 10s -b 32 -c 1,2 --rtprio 1')
        self.run_cmd('oslat -z -D 10s -b 32 -c 1,2 -f 1')

    def test_bucket_width(self):
        if subprocess.run("oslat --help | grep bucket-width",
                          stdout=subprocess.DEVNULL,
                          shell=True).returncode == 0:
            self.run_cmd('oslat -z -D 10s -b 32 --bucket-width 1000')
            self.run_cmd('oslat -z -D 10s -b 32 --bucket-width 100')
            self.run_cmd('oslat -z -D 10s -b 32 --bucket-width 10')
            self.run_cmd('oslat -z -D 10s -b 32 --bucket-width 1')
            self.run_cmd('oslat -z -D 10s -b 32 -W 10')

    def test_short(self):
        self.run_cmd('oslat -b 64 -B -c 1,2 -C 1 -D 10s -m 4K -s -T 10000000 -w no -z')

if __name__ == '__main__':
    OslatTest.run_unittests()
