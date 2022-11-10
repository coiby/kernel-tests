#!/usr/bin/python
# Helper classes for driving command line utilities.

import subprocess
import os
import glob
import re
import logging

class cmd_wrapper():
    """Wrapper for running shell commands"""
    def __init__(self):
        self.cmd = ""
        self.stdout = ""
        self.stderr = ""
        self.retcode = ""
        self.shell = True
        self.logger = logging.getLogger("cmd_helper.cmd_wrapper")

    def run_cmd(self, cmd, shell=True):
        self.cmd = cmd
        self.logger.info("Running Command..: %s", self.cmd)
        p = subprocess.Popen(self.cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=shell)
        self.stdout, self.stderr = p.communicate()
        self.retcode = p.returncode
        self.logger.info("STDOUT: " + self.stdout)
        self.logger.info("STDERR: %s", self.stderr)
        self.logger.info("RC: %s", self.retcode)
        return self.stdout, self.stderr, self.retcode

    def dev_mount(self, dev, mnt_pt):
        if '/' not in dev:
            dev = '/dev/' + dev
        cmd = "mount {0} {1}".format(dev, mnt_pt)
        out = self.run_cmd(cmd)
        if out[2] != 0:
            raise IOError(cmd + " Failed: " + out[1])

    def dev_umount(self, mnt_pt):
        cmd = "umount {0}".format(mnt_pt)
        out = self.run_cmd(cmd)
        if out[2] != 0:
            raise IOError(cmd + " Failed: " + out[1])

    def drop_caches(self):
        cmd = "echo 1 > /proc/sys/vm/drop_caches"
        out = self.run_cmd(cmd)
        if out[2] != 0:
            raise IOError(cmd + " Failed: " + out[1])

class handle_mount(cmd_wrapper):
    def __init__(self, dev, mt_pt):
        cmd_wrapper.__init__(self)
        self.dev = dev
        self.mt_pt = mt_pt
    def __enter__(self):
        cmd_wrapper.dev_mount(self, self.dev, self.mt_pt)
        return True
    def __exit__(self, type, value, traceback):
        cmd_wrapper.dev_umount(self, self.mt_pt)


class dt(cmd_wrapper):
    def __init__(self, dt_bin=None):
        cmd_wrapper.__init__(self)
        self.dt_bin = dt_bin
        self.test_size = 1073741824 # default 1GB
        self.test_dev = None
        self.mount_pt = None
        self.test_pattern = "0xDEADBEEF"
        self.blocksize = 65536
        self.iotype = "sequential"
        self.dispose = "keep"
        self.testfile = "dt-testfile"
        if self.dt_bin:
            if not (os.path.isfile(self.dt_bin) and os.access(self.dt_bin, os.X_OK)):
                raise OSError("No dt binary found at " + self.dt_bin)
        else:
            dt_paths = ["/sbin/dt", "/usr/sbin/dt"]
            for p in dt_paths:
                if os.path.isfile(p) and os.access(p, os.X_OK):
                    self.dt_bin = p
                    break
        if not self.dt_bin:
            raise ValueError("Please make sure dt executable is in either /sbin or /usr/sbin or specify the path when this class is instantiated")

    def run(self, **kwargs):
        iotype = kwargs.get("iotype", self.iotype)
        if iotype == "sequential":
            self.testfile = self.testfile + "-seq"
        elif iotype == "random":
            self.testfile = self.testfile + "-rnd"
        else:
            raise ValueError("iotype must be either sequential or random")
        mount_pt = kwargs.get("mount_pt", self.mount_pt)
        if not mount_pt:
            raise ValueError("Must provide a mount point to run the test")
        else:
            if not os.path.isdir(mount_pt):
                raise OSError("mount point: {0} does not exist".format(mount_pt))
        test_size = kwargs.get("test_size", self.test_size)
        cmd = self.dt_bin + " pattern=" + self.test_pattern + " bs=" + str(self.blocksize) + " of=" + mount_pt + "/" + self.testfile + " iotype=" + iotype + " dispose=" + self.dispose + " limit=" + str(test_size)
        return cmd_wrapper.run_cmd(self, cmd)


# get info on block devices
class block_dev_info():
    """ Return information on block devices on the system """
    def __init__(self):
        self.sys_block_root = "/sys/class/block/"
        self.dev_root = "/dev/"
        self.last_slash_pat = re.compile(r'([^/]+$)')
        self.partition_pat = re.compile(r'(sd[a-z]{1,2}|hd[a-z]{1,2}|cciss/c[0-9]d[0-9]p|nvme[0-9]n[0-9]p|mmcblk[0-9]{1,2}p)[0-9]{1,2}$')
        self.detected_devs = []
        self.detected_devs = self.detect_devs()
        self.usb_scsi_devs = []
        self.usb_scsi_devs = self.find_usb_scsi()

    def get_sector_size(self, blkdev):
        sector_file = self.sys_block_root + '/' + self.get_base_device(blkdev) + '/queue/hw_sector_size'
        return int(open(sector_file).read().rstrip('\n'))

    def get_number_sectors(self, blkdev):
        size_file = self.sys_block_root + '/' + blkdev + '/size'
        return int(open(size_file).read().rstrip('\n'))

    def get_size_in_bytes(self, blkdev):
        return self.get_number_sectors(blkdev) * self.get_sector_size(blkdev)

    def detect_devs(self):
        """ return list of block devices found in /sys/class/block """
        full_devs = glob.glob(self.sys_block_root + '*')
        return [re.search(self.last_slash_pat, dev).group(0) for dev in full_devs]

    def find_usb_scsi(self):
        """ Take list of devices (without /dev) and
        return list of scsi block devices (sd*) which use USB """
        usbdevs = []
        for d in self.detected_devs:
            if "usb" in os.readlink(self.sys_block_root + d):
                usbdevs.append(d)
        return [re.search(self.last_slash_pat, dev).group(0) for dev in usbdevs]

    def is_partition(self, blkdev):
        """ Return True if partition otherwise return False """
        if re.match(self.partition_pat, blkdev):
            return True
        else:
            return False

    def get_base_device(self, blkdev):
        """ given device name pointing to a partition (e.g. /dev/sda1),
            return the base dev name. If there is no partion, then return
            the device name unchanged """
        if self.is_partition(blkdev):
            if blkdev.startswith("mmc"):
                return re.search(r'(mmcblk[0-9]{1,2})p[0-9]{1,2}', blkdev).group(1)
            else:
                return re.search(self.partition_pat, blkdev).group(1)
        else:
            return blkdev

    def get_largest_block_dev(self, blkdevs):
        """ return the largest partition/device from list of devices/partitions """
        if len(blkdevs) > 1:
            d = {}
            for dev in blkdevs:
                d[dev] = self.get_size_in_bytes(dev)
            return max(d, key=lambda k: d[k])
        else:
            return blkdevs[0]

