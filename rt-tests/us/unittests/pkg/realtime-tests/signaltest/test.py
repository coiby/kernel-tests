#!/usr/bin/python3
"""
Unittest for signaltest of realtime-tests
"""
import os
import rtut

class SignaltestTest(rtut.RTUnitTest):

    def setUp(self):
        self.tmp_file = f"{os.getcwd()}/output.json"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help_short(self):
        self.run_cmd('signaltest -h')

    def test_help_long(self):
        self.run_cmd('signaltest --help')

    def test_short(self):
        self.run_cmd('signaltest -a 0,1 -b 100000 -D 5 -m -p 50 -q -t 2 -v')

    def test_short_loops(self):
        # If loops are > 0, signaltest will not honour -D/--duration
        self.run_cmd('signaltest -l 2')

    def test_long_loops(self):
        # If loops are > 0, signaltest will not honour -D/--duration
        self.run_cmd('signaltest --loops 2')

    def test_long(self):
        self.run_cmd('signaltest --affinity 0,1 --breaktrace=100000 --duration 10s '
                     f' --json={self.tmp_file} --mlockall --prio=80 --quiet '
                     '--threads=2 --verbose')

if __name__ == '__main__':
    SignaltestTest.run_unittests()
