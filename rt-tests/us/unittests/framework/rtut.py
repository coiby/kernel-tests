#!/usr/bin/python3
"""
RTUT (Real Time Unit Test) Framework
"""
import unittest
import subprocess
import inspect

class RTUnitTest(unittest.TestCase):
    """ Class for unittest methods for RT userspace packages """

    def setUp(self):
        """
        User may override this function to provide some initialization to
        be used throughout the tests.  This can be useful to initialize
        items like pids/threads that need to run for the duration of the
        unittest that can later be torn down as to not modify the
        behaviour of the system and skew subsequent results/tests.
        """
        return

    def tearDown(self):
        """
        User may override this function to cleanup anything initialized
        during setUp or testing
        """
        return

    def run_cmd(self, cmd, status=0):
        """ Execute the unittest by executing the shell cmd arg """
        ret, out = subprocess.getstatusoutput(cmd)
        caller = inspect.stack()[1].function
        self.report_result(caller, cmd, out, ret, status)
        self.assertEqual(status, ret)

    @staticmethod
    def report_result(testname, command, out, ret, status):
        """ Pretty print unittest output and report via restraint """
        result = 'PASS' if ret == status else 'FAIL'
        print("\n")
        print("=" * 70)
        print(f"{result} || {command} [{testname}]")
        print(f"     || Expected: {status}, Got: {ret}")
        print("-" * 70)
        print(f"{out}\n")
        subprocess.getstatusoutput(f'/usr/bin/rstrnt-report-result {testname} {result} {ret}')

    @classmethod
    def run_unittests(cls):
        """ Class method for running the unittest main function """
        print(f"Running unittest for {cls.__name__}")
        unittest.main(verbosity=2)

if __name__ == '__main__':
    raise RuntimeError(f"{__file__.rsplit('/', 1)[-1]} to be imported "
                       "as a module, not run as a script")
