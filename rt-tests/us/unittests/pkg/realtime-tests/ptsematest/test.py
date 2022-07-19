#!/usr/bin/python3
"""
Unittest for ptsematest of realtime-tests
"""
import os
import rtut

class PtsematestTest(rtut.RTUnitTest):

    def setUp(self):
        self.tmp_file = f"{os.getcwd()}/output.json"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help_short(self):
        self.run_cmd('ptsematest -h')

    def test_help_long(self):
        self.run_cmd('ptsematest --help')

    def test_short(self):
        self.run_cmd('ptsematest -a 1 -b 1000000 -d 600 -D 5 -q -i 2000 -l 2 -p 60 -t 2 -S')

    def test_long(self):
        self.run_cmd('ptsematest -affinity=1 -breaktrace=1000000 --duration=5 --distance=600 '
                    f'--json {self.tmp_file} --quiet --interval=2000 --loops=2 '
                    '--prio=60 --threads=2 --smp')

if __name__ == '__main__':
    PtsematestTest.run_unittests()
