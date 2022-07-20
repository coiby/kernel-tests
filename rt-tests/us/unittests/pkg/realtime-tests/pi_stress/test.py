#!/usr/bin/python3
"""
Unittest for pi_stress of realtime-tests
"""
import os
import rtut

class PiStressTest(rtut.RTUnitTest):

    def setUp(self):
        self.tmp_file = f"{os.getcwd()}/output.json"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help_long(self):
        self.run_cmd('pi_stress --help')

    def test_help_short(self):
        self.run_cmd('pi_stress -h')

    def test_vers_short(self):
        self.run_cmd('pi_stress -V')

    def test_vers_long(self):
        self.run_cmd('pi_stress --version')

    def test_short(self):
        self.run_cmd('pi_stress -d -D 10 -g 2 -i 1000 -m -q -r -s id="med" -u -v')

    def test_long(self):
        self.run_cmd('pi_stress --debug --duration 10 --groups 2 --inversions 1000 '
                     f' --json={self.tmp_file} --mlockall --quiet --rr '
                     '--sched id="med" --uniprocessor --verbose')

if __name__ == '__main__':
    PiStressTest.run_unittests()
