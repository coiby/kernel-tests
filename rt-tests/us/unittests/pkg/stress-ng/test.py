#!/usr/bin/python3
"""
Unittest for package stress-ng
"""
import os
import rtut

class StressNgTest(rtut.RTUnitTest):

    def setUp(self):
        self.cpulist = "1"
        self.tmp_file = f"{os.getcwd()}/output.txt"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help_short(self):
        self.run_cmd(f'stress-ng -h')

    def test_help_long(self):
        self.run_cmd(f'stress-ng --help')

    def test_mmap(self):
        self.run_cmd(f'stress-ng --cpu {self.cpulist} --io 4 --vm 2 --vm-bytes 56M --fork 4 --timeout 5s')

    def test_hdd_scheduling_latencies(self):
        self.run_cmd(f'stress-ng --cyclic 1 --cyclic-dist 2500 --cyclic-method clock_ns --cyclic-prio 100 --cyclic-sleep 10000 --hdd 0 -t 1m')

    def test_parallel(self):
        self.run_cmd(f'stress-ng --all 4 --timeout 5s')

    def test_taskset(self):
        self.run_cmd(f'stress-ng --taskset 0,1 --cpu 3 --timeout 5s')

    def test_maximize(self):
        self.run_cmd(f'stress-ng --all -1 --maximize --aggressive')

    def test_different_cpu_stressors(self):
        self.run_cmd(f'stress-ng --cpu {self.cpulist} --cpu-method all --verify -t 10s --metrics-brief')

if __name__ == '__main__':
    StressNgTest.run_unittests()
