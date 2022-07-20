#!/usr/bin/python3
"""
Unittest for cyclicdeadline of realtime-tests
"""
import os
import rtut

class CyclicDeadlineTest(rtut.RTUnitTest):

    def setUp(self):
        self.tmp_file = f"{os.getcwd()}/output.json"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help(self):
        self.run_cmd('cyclicdeadline --help')

    def test_short(self):
        self.run_cmd('cyclicdeadline -a 0,1 -D 10 -i 10000 -s 1000 -t 2 -q')

    def test_long(self):
        self.run_cmd('cyclicdeadline --affinity 0,1 --duration 10 --interval 10000 '
                     f'--json={self.tmp_file} --step 500 --step 500 --threads 2 --quiet')

if __name__ == '__main__':
    CyclicDeadlineTest.run_unittests()
