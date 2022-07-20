#!/usr/bin/python3
"""
Unittest for package tuna
"""
import os
import subprocess
import rtut

class TunaTest(rtut.RTUnitTest):

    def setUp(self):
        # pylint: disable=R1732
        self.fnull = open(os.devnull, 'w', encoding="utf-8")
        self.thrdplay = subprocess.Popen(["vmstat", "1", "5000"], stdout=self.fnull)
        self.pidplay = self.thrdplay.pid
        self.tmp_file = f"{os.getcwd()}/output.txt"

    def tearDown(self):
        self.thrdplay.terminate()
        self.thrdplay.wait()
        self.fnull.close()
        if os.path.exists(self.tmp_file):
            os.remove(self.tmp_file)

    def test_threads_prio_fifo(self):
        self.run_cmd(f'tuna --threads={self.pidplay} --priority=FIFO:40')

    def test_threads_prio_rr(self):
        self.run_cmd('tuna --threads=vmstat --priority=RR:50 --show_threads')

    def test_version(self):
        self.run_cmd('tuna -v')

    def test_show_threads(self):
        self.run_cmd('tuna --threads=vmstat --show_threads')

    def test_what_is(self):
        self.run_cmd('tuna --threads=vmstat -W')

    def test_cgroup(self):
        self.run_cmd('tuna -G -P')

    def test_show_irqs(self):
        self.run_cmd('tuna --show_irqs')

    def test_show_irqs_by_user(self):
        self.run_cmd('tuna --irqs=timer --show_irqs')

    def test_save(self):
        self.run_cmd(f'tuna --save={self.tmp_file}')

    def test_isoate(self):
        self.run_cmd(f'tuna --threads={self.pidplay} --cpus=0 --isolate')

    def test_spread(self):
        self.run_cmd(f'tuna --threads={self.pidplay} --cpus=0,1 --spread')

    def test_include(self):
        self.run_cmd('tuna --cpus=0,1 --include --run="ps -ef"')

    def test_affect_children(self):
        self.run_cmd('tuna --cpus=0,1 --affect_children --include --run="ps -ef"')

    def test_filter(self):
        self.run_cmd('tuna --threads=vmstat --show_threads --filter -c 0')

    def test_no_kthreads(self):
        self.run_cmd('tuna --cpus=0,1 --no_kthreads --include --run="ps -ef"')

    def test_move(self):
        self.run_cmd(f'tuna --threads={self.pidplay} --cpus=0 --move')

    def test_run(self):
        self.run_cmd('tuna --cpus=0,1 --run="ps -ef"')

    def test_sockets(self):
        self.run_cmd('tuna --sockets=0')

if __name__ == '__main__':
    TunaTest.run_unittests()
