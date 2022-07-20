#!/usr/bin/python3
"""
Unittest for pmqtest of realtime-tests
"""
import rtut

class PmqtestTest(rtut.RTUnitTest):

    def test_help_short(self):
        self.run_cmd('pmqtest -h')

    def test_help_long(self):
        self.run_cmd('pmqtest --help')

    def test_short(self):
        self.run_cmd('pmqtest -a 1 -b 1000000 -d 600 -D 5 -f 5000 '
                     '-T 50000 -q -i 2000 -l 2 -p 60 -t 2 -S')

    def test_long(self):
        self.run_cmd('pmqtest -affinity=1 -breaktrace=1000000 --duration=5 '
                     '--forcetimeout=5000 --timeout 50000 --quiet --interval=2000 '
                     '--loops=2 --prio=60 --threads=2 --smp')

if __name__ == '__main__':
    PmqtestTest.run_unittests()
