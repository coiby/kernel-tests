#!/usr/bin/python3
import unittest
import subprocess
import inspect
import os, signal

def show_details(testname, command, status=' PASS '):
    print("Run status -- {0}, testname -- {1} , command is -- {2}".format(status, testname, command))

class TestCmdValid(unittest.TestCase):
    """ Class for unittest methods """
    def setUp(self):
        self.fail = "FAIL"
        self.passed = "PASS"
        self.e = ""
        self.cpulist = "0"

    def passtst(self, testname, command):
        """ Report that the test passed """
        show_details(testname, command)
        subprocess.getstatusoutput('/usr/bin/rstrnt-report-result {0} {1} {2}'.format(testname, self.passed, 0))

    def failtst(self, testname, command):
        """ Report that the test failed """
        show_details(testname, command, status=' FAIL ')
        subprocess.getstatusoutput('/usr/bin/rstrnt-report-result {0} {1} {2}'.format(testname, self.fail, 0))

    def runtst(self, cmd):
        """ Execute the unittest """
        rc, _ = subprocess.getstatusoutput(cmd)
        caller = inspect.stack()[1].function
        try:
            self.assertEqual(0, rc)
        except AssertionError as e:
            self.e = e
            if self.e:
                self.failtst(caller, cmd)
                raise
        self.passtst(caller, cmd)

    def test_cpulist(self):
        self.runtst('timeout --preserve-status 2 stalld -f -c {0}'.format(self.cpulist))

    def test_help(self):
        self.runtst('stalld -h')

    def test_boost_runtime(self):
        self.runtst('timeout --preserve-status 2 stalld -f -r 1000000')

    def test_boost_period(self):
        self.runtst('timeout --preserve-status 2 stalld -f -p 200000000')

    def test_boost_period(self):
        self.runtst('timeout --preserve-status 2 stalld -f -p 200000000')

    def test_duration_time(self):
        self.runtst('timeout --preserve-status 10 stalld -f -d 2 -t 3')
    
    def test_logging_verbose(self):
        self.runtst('timeout --preserve-status 2 stalld -f -l -v')

    def test_kmsg_syslog(self):
        self.runtst('timeout --preserve-status 2 stalld -f -k -s')

    def test_force_fifo(self):
        self.runtst('timeout --preserve-status 2 stalld -f -F')

    def test_aggressive_power_gran(self):
        self.runtst('timeout --preserve-status 2 stalld -f -A -O -g 1')

    def test_ignore_thread(self):
        self.runtst('timeout --preserve-status 2 stalld -f -i foo')

    def test_ignore_proc(self):
        self.runtst('timeout --preserve-status 2 stalld -f -I foo')

    def test_pidfile(self):
        self.runtst('timeout --preserve-status 2 stalld -f --pidfile /tmp/stalldPid')

    def test_systemd(self):
        self.runtst('timeout --preserve-status 2 stalld -f -S')

    def test_logging_single(self):
        self.runtst('timeout --preserve-status 2 stalld -f -l -O')

if __name__ == '__main__':
    unittest.main()

