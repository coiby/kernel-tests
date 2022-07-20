#!/usr/bin/python3
"""
Unittest for deadline_test of realtime-tests
"""
import rtut

class DeadlinetestTest(rtut.RTUnitTest):

    def test_help(self):
        self.run_cmd('deadline_test -h')

    def test_short(self):
        self.run_cmd('deadline_test -b -c 0,1 -i 100000 -p 80 -P 99 -r FIFO -s 1000 -t 2')

if __name__ == '__main__':
    DeadlinetestTest.run_unittests()
