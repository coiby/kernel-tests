#!/usr/bin/python3
"""
Unittest for sigwaittest of realtime-tests
"""
import os
import rtut

class SigwaittestTest(rtut.RTUnitTest):

    def setUp(self):
        self.tmp_file = f"{os.getcwd()}/output.json"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help_short(self):
        self.run_cmd('sigwaittest -h')

    def test_help_long(self):
        self.run_cmd('sigwaittest --help')

    def test_short(self):
        self.run_cmd('sigwaittest -a 0,1 -d 1000 -b 100000 -D 5 -i 2000 -p 50 -q -t 2')

    def test_short_loops(self):
        # If loops are > 0, sigwaittest will not honour -D/--duration
        self.run_cmd('sigwaittest -l 2 -f')

    def test_long_loops(self):
        # If loops are > 0, sigwaittest will not honour -D/--duration
        self.run_cmd('sigwaittest --loops 2 --fork')

    def test_long(self):
        self.run_cmd('sigwaittest --affinity 0,1 --breaktrace=100000 --duration 10s '
                     f'--json={self.tmp_file} --interval=2000 --prio=80 --quiet --threads=2')

if __name__ == '__main__':
    SigwaittestTest.run_unittests()
