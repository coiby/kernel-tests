#!/usr/bin/python3
"""
Unittest for cyclictest of realtime-tests
"""
import os
import rtut
import subprocess

class CyclictestTest(rtut.RTUnitTest):

    def setUp(self):
        is_longname = subprocess.getstatusoutput("rpm -q realtime-tests")[0]
        self.tmp_file = f"{os.getcwd()}/output_or_pipe"
        self.pkgname = "realtime-tests" if is_longname == 0 else "rt-tests"
        self.pkgnvr = subprocess.getoutput(f"rpm -q {self.pkgname}")

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help(self):
        self.run_cmd('cyclictest --help')

    def test_short_one(self):
        self.run_cmd('cyclictest -a 0 -A 1000000 -D 5 -b 10000 -c 1 -d 600 '
                     '-h 5 -H 5 -i 2000 -l 2 -m -M -N')

    def test_short_two(self):
        self.run_cmd('cyclictest -p 60 -D 2 -q -v')

    def test_short_three(self):
        self.run_cmd('cyclictest -p 60 -D 2 -q -r -s -t 2')

    def test_short_four(self):
        self.run_cmd('cyclictest -p 60 -D 2 -q -r -S 2 -u -d 600')

    def test_short_five(self):
        self.run_cmd('cyclictest -p 60 -D 2 -q -x -R')

    def test_long_one(self):
        self.run_cmd('cyclictest --affinity 0 --duration=2 --aligned=1000000 '
                     '--breaktrace=10000 --clock=1')

    def test_long_two(self):
        self.run_cmd('cyclictest --distance=600 --duration=2 --latency=PM_QOS '
                     f'--histogram=5 --histofall=5 --histfile={self.tmp_file}')

    def test_long_three(self):
        self.run_cmd(f'cyclictest --duration=2 --interval=2000 --json={self.tmp_file} '
                     '--loops=2 --laptop --mainaffinity=0')

    def test_long_four(self):
        self.run_cmd('cyclictest --duration=2 --mlockall --refresh_on_max --nsecs '
                     '--priority=60 --priospread')

    def test_long_five(self):
        self.run_cmd('cyclictest --duration=2 --quiet --relative --resolution '
                     '--secaligned --system')

    def test_long_six(self):
        self.run_cmd('cyclictest --duration=2 --smp --spike=3000 '
                     '--spike-nodes=1 --threads=3')

    def test_long_seven(self):
        self.run_cmd('cyclictest --duration=2 --tracemark --unbuffered --verbose '
                     '--dbg_cyclictest --posix_timers')

    def test_fifo_short(self):
        self.run_cmd(f'cyclictest -F {self.tmp_file} --duration 5')

    def test_fifo_long(self):
        self.run_cmd(f'cyclictest --fifo {self.tmp_file} --duration 5')

    def test_cpupower(self):
        # https://issues.redhat.com/browse/RHEL-65487
        ret = subprocess.getstatusoutput(f"rpmdev-vercmp "
                                         f"{self.pkgnvr} "
                                         f"realtime-tests-2.8-2")[0]
        if ret == 11:
            self.run_cmd(f"cyclictest --deepest-idle-state=1 --duration=1")

if __name__ == '__main__':
    CyclictestTest.run_unittests()
