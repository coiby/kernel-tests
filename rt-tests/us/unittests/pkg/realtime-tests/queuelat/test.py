#!/usr/bin/python3
"""
Unittest for queuelat of realtime-tests
"""
import rtut

class QueuelatTest(rtut.RTUnitTest):

    def test_help_long(self):
        self.run_cmd('queuelat --help')

    def test_help_short(self):
        self.run_cmd('queuelat -h')

    def test_long(self):
        self.run_cmd('queuelat --cycles 100 --freq 100 --max-len 100000 --packets 100000 '
                     '--queue-len 100 --timeout 10')

    def test_short(self):
        self.run_cmd('queuelat -c 100 -f 100 -m 100000 -p 100000 -q 100 -t 10')

if __name__ == '__main__':
    QueuelatTest.run_unittests()
