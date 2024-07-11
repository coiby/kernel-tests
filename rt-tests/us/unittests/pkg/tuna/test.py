#!/usr/bin/python3
"""
Unittest for package tuna
"""
import os
import subprocess
import rtut
import re

class TunaTest(rtut.RTUnitTest):

    def setUp(self):
        # pylint: disable=R1732
        self.fnull = open(os.devnull, 'w', encoding="utf-8")
        self.thrdplay = subprocess.Popen(["vmstat", "1", "5000"], stdout=self.fnull)
        self.pidplay = self.thrdplay.pid
        self.tmp_file = f"{os.getcwd()}/output.txt"
        f = open("/etc/redhat-release", "r")
        self.rhel_version = float(re.findall(r"\d+\.\d+", f.read().rstrip())[0])
        f.close()

    def tearDown(self):
        self.thrdplay.terminate()
        self.thrdplay.wait()
        self.fnull.close()
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_threads_prio_fifo(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna priority FIFO:40 --threads={self.pidplay}')
        else:
            self.run_cmd(f'tuna --threads={self.pidplay} --priority=FIFO:40')

    def test_threads_prio_rr(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna priority RR:50 --threads=vmstat')
        else:
            self.run_cmd('tuna --threads=vmstat --priority=RR:50 --show_threads')

    def test_version(self):
        self.run_cmd('tuna -v')

    def test_show_threads(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna show_threads --threads=vmstat')
        else:
            self.run_cmd('tuna --threads=vmstat --show_threads')

    def test_what_is(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna what_is vmstat')
        else:
            self.run_cmd('tuna --threads=vmstat -W')

    def test_cgroup(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna show_threads -G')
        else:
            self.run_cmd('tuna -G -P')

    def test_show_irqs(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna show_irqs')
        else:
            self.run_cmd('tuna --show_irqs')

    def test_show_irqs_by_user(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna show_irqs --irqs=rtc0')
        else:
            self.run_cmd('tuna --irqs=rtc0 --show_irqs')

    def test_save(self):
        if self.rhel_version >= 9.2:
            self.run_cmd(f'tuna save {self.tmp_file}')
        else:
            self.run_cmd(f'tuna --save={self.tmp_file}')

    def test_isolate(self):
        if self.rhel_version >= 9.2:
            self.run_cmd(f'tuna isolate --cpus 0')
        else:
            self.run_cmd(f'tuna --threads={self.pidplay} --cpus=0 --isolate')

    def test_spread(self):
        if self.rhel_version >= 9.2:
            self.run_cmd(f'tuna spread --threads={self.pidplay} --cpus=0,1')
        else:
            self.run_cmd(f'tuna --threads={self.pidplay} --cpus=0,1 --spread')

    def test_include(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna include --cpus 0,1')
        else:
            self.run_cmd('tuna --cpus=0,1 --include --run="ps -ef"')

    def test_affect_children(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna show_threads --cpus 0,1 --affect_children')
        else:
            self.run_cmd('tuna --cpus=0,1 --affect_children --include --run="ps -ef"')

    def test_filter(self):
        if self.rhel_version < 9.2:
            self.run_cmd('tuna --threads=vmstat --show_threads --filter -c 0')

    def test_no_kthreads(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna show_threads --threads vmstat --cpus 0,1 --no_kthreads')
        else:
            self.run_cmd('tuna --cpus=0,1 --no_kthreads --include --run="ps -ef"')

    def test_move(self):
        if self.rhel_version >= 9.2:
            self.run_cmd(f'tuna move --threads={self.pidplay} --cpus=0')
        else:
            self.run_cmd(f'tuna --threads={self.pidplay} --cpus=0 --move')

    def test_run(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna run "ps -ef" --cpus 0,1')
        else:
            self.run_cmd('tuna --cpus=0,1 --run="ps -ef"')

    def test_sockets(self):
        if self.rhel_version >= 9.2:
            self.run_cmd('tuna show_threads --sockets 0')
        else:
            self.run_cmd('tuna --sockets=0')

if __name__ == '__main__':
    TunaTest.run_unittests()
