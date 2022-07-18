#!/usr/bin/python3
"""
Unittest for package python-ethtool
"""
import subprocess
import re
import rtut

class PythonEthtoolTest(rtut.RTUnitTest):

    def setUp(self):
        self.interface = self.get_an_interface()
        self.c_val = self.get_coalesce_val()
        self.r_val = self.get_ring_val()

    @staticmethod
    def get_an_interface():
        cmd = subprocess.getoutput('ip link show')
        pattern = re.compile(r"\d:\s(\w+):\s<BROADCAST,MULTICAST,UP.*")
        inter = re.search(pattern, cmd)
        if inter:
            return inter.group(1)
        raise RuntimeError("No interface with BROADCAST,MULTICAST,UP found: cannot continue")

    def get_coalesce_val(self):
        cmd = subprocess.getoutput(f'pethtool -c {self.interface}')
        pattern = re.compile(r"(rx-\w+):\s(\d+).*")
        col = re.search(pattern, cmd)
        if col:
            return (col.group(1), col.group(2))
        raise RuntimeError(f"No rx-* value found with 'pethtool -c {self.interface}'")

    def get_ring_val(self):
        cmd = subprocess.getoutput(f'pethtool -g {self.interface}')
        pattern = re.compile(r"rx:\s+(\d+).*",re.IGNORECASE)
        ring = re.search(pattern, cmd)
        if ring:
            return ring.group(1)
        raise RuntimeError(f"No RX value found with 'pethtool -g {self.interface}'")

    def test_help(self):
        self.run_cmd('pethtool -h')

    def test_coalesce(self):
        self.run_cmd('pethtool -c')

    def test_coalesce_mod(self):
        val = int(self.c_val[1]) + 1
        self.run_cmd(f'pethtool -C {self.interface} {self.c_val[0]} {val}')
        self.run_cmd(f'pethtool -C {self.interface} {self.c_val[0]} {val - 1}')

    def test_show_ring(self):
        self.run_cmd('pethtool -g')

    def test_set_ring(self):
        val = int(self.r_val) + 1
        self.run_cmd(f'pethtool -G {self.interface} {self.r_val[0]} {val}')
        self.run_cmd(f'pethtool -G {self.interface} {self.r_val[0]} {val - 1}')

    def test_info(self):
        self.run_cmd(f'pethtool -i {self.interface}')

    def test_offload(self):
        self.run_cmd(f'pethtool -k {self.interface}')

if __name__ == '__main__':
    PythonEthtoolTest.run_unittests()
