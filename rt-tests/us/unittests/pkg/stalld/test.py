#!/usr/bin/python3
"""
Unittest for package stalld
"""
import os
import rtut

class StalldTest(rtut.RTUnitTest):

    def setUp(self):
        self.cpulist = "0"
        self.tmp_file = f"{os.getcwd()}/pidfile"

    def tearDown(self):
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_help(self):
        self.run_cmd('stalld -h')

    def test_cpulist(self):
        self.run_cmd(f'timeout --preserve-status 2 stalld -f -c {self.cpulist}')

    def test_boost_runtime(self):
        self.run_cmd('timeout --preserve-status 2 stalld -f -r 1000000')

    def test_boost_period(self):
        self.run_cmd('timeout --preserve-status 2 stalld -f -p 200000000')

    def test_duration_time(self):
        self.run_cmd('timeout --preserve-status 10 stalld -f -d 2 -t 3')

    def test_logging_verbose(self):
        self.run_cmd('timeout --preserve-status 2 stalld -f -l -v')

    def test_kmsg_syslog(self):
        self.run_cmd('timeout --preserve-status 2 stalld -f -k -s')

    def test_force_fifo(self):
        self.run_cmd('timeout --preserve-status 2 stalld -f -F')

    def test_aggressive_power_gran(self):
        self.run_cmd('timeout --preserve-status 2 stalld -f -A -O -g 1')

    def test_ignore_thread(self):
        self.run_cmd('timeout --preserve-status 2 stalld -f -i foo')

    def test_ignore_proc(self):
        self.run_cmd('timeout --preserve-status 2 stalld -f -I foo')

    def test_pidfile(self):
        self.run_cmd(f'timeout --preserve-status 2 stalld -f --pidfile {self.tmp_file}')

    # -S/--systemd: running as systemd service, don't fiddle with RT throttling
    # Note: The -S option does not modify RT throttling settings, and stalld will fail to run if throttling is active.
    def test_systemd(self):
        rt_runtime_file = "/proc/sys/kernel/sched_rt_runtime_us"
        if os.path.exists(rt_runtime_file):
            with open(rt_runtime_file, 'r') as f:
                rt_runtime_value = f.read().strip()
            if rt_runtime_value == "950000":
                self.skipTest("RT throttling is enabled (value is 950000), skipping test.")
        self.run_cmd('timeout --preserve-status 2 stalld -f -S')

    def test_logging_single(self):
        self.run_cmd('timeout --preserve-status 2 stalld -f -l -O')

if __name__ == '__main__':
    StalldTest.run_unittests()
