#!/usr/bin/python3
"""
Unittest for cyclicdeadline of realtime-tests
"""
import os
import rtut
import subprocess

class CyclicDeadlineTest(rtut.RTUnitTest):

    def setUp(self):
        is_longname = subprocess.getstatusoutput("rpm -q realtime-tests")[0]
        self.tmp_file = f"{os.getcwd()}/output.json"
        self.pkgname = "realtime-tests" if is_longname == 0 else "rt-tests"
        self.pkgnvr = subprocess.getoutput(f"rpm -q {self.pkgname}")
        self.nrcpus = int(subprocess.getoutput(f"grep -c processor /proc/cpuinfo"))
        self.opt_affinity = "0" if self.nrcpus == 1 else "0,1"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help(self):
        self.run_cmd('cyclicdeadline --help')

    def test_short(self):
        self.run_cmd(f"cyclicdeadline -a {self.opt_affinity} -D 10 -i 10000 -s 1000 -t 2 -q")

    def test_long(self):
        self.run_cmd(f"cyclicdeadline --affinity {self.opt_affinity} "
                     f"--duration 10 --interval 10000 --json={self.tmp_file} "
                     f"--step 500 --step 500 --threads 2 --quiet")

    def test_hist(self):
        # https://issues.redhat.com/browse/RHEL-9910
        ret = subprocess.getstatusoutput(f"rpmdev-vercmp "
                                         f"{self.pkgnvr} "
                                         f"realtime-tests-2.6-2.el9")[0]
        if ret == 11:
            self.run_cmd(f"cyclicdeadline --histogram=5us --histfile={self.tmp_file} --duration=10")

if __name__ == '__main__':
    CyclicDeadlineTest.run_unittests()
