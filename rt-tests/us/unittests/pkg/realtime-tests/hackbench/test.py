#!/usr/bin/python3
"""
Unittest for hackbench of realtime-tests
"""
import rtut

class HackbenchTest(rtut.RTUnitTest):

    def test_help(self):
        self.run_cmd('hackbench -h')

    def test_long_threads(self):
        self.run_cmd('hackbench --fds=2 --groups=3 --loops=4 --fifo '
                     '--pipe --datasize=1 --threads')

    def test_long_process(self):
        self.run_cmd('hackbench --fds=2 --groups=3 --loops=4 --fifo '
                     '--pipe --datasize=1 --process')

    def test_short_threads(self):
        self.run_cmd('hackbench -f 2 -g 3 -l 4 -F -p -s 1 -T')

    def test_short_process(self):
        self.run_cmd('hackbench -f 2 -g 3 -l 4 -F -p -s 1 -P')

if __name__ == '__main__':
    HackbenchTest.run_unittests()
