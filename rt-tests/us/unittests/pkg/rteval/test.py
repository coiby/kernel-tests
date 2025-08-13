#!/usr/bin/python3
"""
Unittest for package rteval
"""
import configparser
import subprocess
import os
import glob
import shutil
import rtut


class RtevalTest(rtut.RTUnitTest):

    @staticmethod
    def check_timerlat_in_measurement():
        config = configparser.ConfigParser()
        config.read("/etc/rteval.conf")

        if "measurement" in config:
            if "timerlat" in config["measurement"]:
                return True
        return False

    def setUp(self):
        cwd = os.getcwd()
        self.wrkdir = f"{cwd}/workingdir"
        self.summary = f"{cwd}/workingdir/*/summary.xml"
        # true if timerlat is the preferred over cyclictest
        timerlat = self.check_timerlat_in_measurement()
        self.preferred_measurement_module = "timerlat" if timerlat else "cyclictest"
        self.make_dirs(self.wrkdir)
        self.cpulist = "0"

    def tearDown(self):
        cwd = os.getcwd()
        self.rm_dirs(self.wrkdir)
        self.rm_dirs(f"{cwd}/rteval-[0-9]*")
        self.rm_dirs(f"{cwd}/rteval-build")

    @staticmethod
    def make_dirs(dirpath):
        try:
            os.makedirs(dirpath)
        except (OSError, FileNotFoundError):
            pass

    @staticmethod
    def rm_dirs(dirpath):
        try:
            # os.rmdir cannot remove non-empty directories, so use
            # shutil.rmtree instead; glob is to support wildcards
            for directory in glob.glob(dirpath):
                shutil.rmtree(directory)
        except (OSError, FileNotFoundError):
            pass

    def test_version(self):
        self.run_cmd("rteval -V")

    def test_help(self):
        self.run_cmd("rteval --help")

    def test_cpu_list(self):
        self.run_cmd(
            f"rteval -d 10s -w {self.wrkdir} -D --loads-cpulist={self.cpulist} "
            f"-L --{self.preferred_measurement_module}-priority=90"
        )

    def test_measurement_cpu_list(self):
        self.run_cmd(
            f"rteval -d 10s -w {self.wrkdir} -s --measurement-cpulist={self.cpulist} "
            f"-L --{self.preferred_measurement_module}-priority=90"
        )

    def test_summarize(self):
        self.run_cmd(f"rteval -d 10s -w {self.wrkdir} && rteval -Z {self.summary}")

    def test_onlyload(self):
        self.run_cmd("rteval -d 10s --onlyload")

    def test_rawhisto(self):
        self.run_cmd(
            f"rteval -d 10s -w {self.wrkdir} && rteval --raw-histogram {self.summary}"
        )

    def test_cyclic_threshold(self):
        ret, _ = subprocess.getstatusoutput(
            "rteval --help | grep -q cyclictest-threshold"
        )
        if ret == 0:
            self.run_cmd("rteval --duration=1m --cyclictest-threshold=1", status=1)


if __name__ == "__main__":
    RtevalTest.run_unittests()
