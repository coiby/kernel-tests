#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""luks.py: Module to run libblockdev luks or mgmt local storage"""

from __future__ import absolute_import, division, print_function, unicode_literals
__author__ = "Guazhang"
__copyright__ = "Copyright (c) 2016 Red Hat, Inc. All rights reserved."

import libsan.host.scsi as scsi
import libsan.host.loopdev as loop
import libsan.host.linux as linux
import libsan.host.mp as mp
import libsan.host.fio as fio
import libsan.host.stratis as stratis
import re
import random
import string
import subprocess
import sys
import os
import json
import time
import tempfile
import uuid
import stat
from contextlib import contextmanager

# https://github.com/storaged-project/libblockdev/tree/master/tests

pks_list = ['libblockdev-crypto', 'libblockdev-dm', 'libblockdev-fs','libblockdev-utils',
        'libblockdev-kbd','libblockdev-loop', 'libblockdev-lvm', 'libblockdev-mdraid','libblockdev-mpath','python3-blockdev',
        'libblockdev-nvdimm', 'libblockdev-part', 'libblockdev-swap', 'libblockdev','python3-gobject-base']
for p in pks_list :
    if not linux.is_installed(p):
        if not linux.install_package(p):
            raise RuntimeError("Could not install package %s" % p)
import gi
gi.require_version("BlockDev", "2.0")
from gi.repository import BlockDev as bd



class Base():
    error_message=''
    def _print(self, string):
        module_name = __name__
        string = re.sub("DEBUG:", "DEBUG:(" + module_name + ") ", string)
        string = re.sub("FAIL:", "FAIL:(" + module_name + ") ", string)
        string = re.sub("FATAL:", "FATAL:(" + module_name + ") ", string)
        string = re.sub("WARN:", "WARN:(" + module_name + ") ", string)

        # Append time information to command
        date = "date \"+%Y-%m-%d %H:%M:%S\""
        p = subprocess.Popen(date, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
        stdout, stderr = p.communicate()
        stdout = stdout.decode('ascii', 'ignore')
        stdout = stdout.rstrip("\n")

        if "FAIL" in string:
            print("[%s] \033[1;31m %s \033[0m" % (stdout, string))
        if "INFO" in string:
            print('[%s] \033[1;32m %s \033[0m' %(stdout, string))

        #sys.stdout.flush()

        if any(e in string for e in ['FAIL','FATAL']):
            self.error_message += '\n %s ' % string
        return


    def run_command(self, command, cmd_input=None):
        res = subprocess.Popen(command, shell=True, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, stdin=subprocess.PIPE)
        out, err = res.communicate(input=cmd_input)
        return (res.returncode, out.decode().strip()+err.decode().strip())


    def run(self, cmd, return_output=False, verbose=True, force_flush=False):
        if verbose:
            date = "date \"+%Y-%m-%d %H:%M:%S\""
            p = subprocess.Popen(date, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
            stdout, stderr = p.communicate()
            stdout = stdout.decode('ascii', 'ignore')
            stdout = stdout.rstrip("\n")
            print("INFO: [%s] Running: '%s'..." % (stdout, cmd))
        stderr = b""
        if not force_flush:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
            stdout, stderr = p.communicate()
            sys.stdout.flush()
            sys.stderr.flush()
        else:
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, shell=True)
            stdout = b""
            while p.poll() is None:
                new_data = p.stdout.readline()
                stdout += new_data
                if verbose:
                    sys.stdout.write(new_data.decode('ascii', 'ignore'))
                sys.stdout.flush()
        retcode = p.returncode
        output = stdout.decode('ascii', 'ignore') + stderr.decode('ascii', 'ignore')
        output = output.rstrip()
        if verbose and not force_flush:
            print(output)
        if not return_output:
            return retcode
        else:
            return retcode, output

    def run_fio(self, of, verbose=False, return_output=False, background=False, **fio_opts):
        if not fio._has_fio():
            fio.install_fio()
        if background :
            return fio.fio_stress_background(of, verbose=False, **fio_opts)
        return fio.fio_stress(of, verbose=False, return_output=False, **fio_opts)

    def range_str(self, num=3):
        return ''.join(random.sample(string.ascii_letters, num))


    def write_env(self,file_name, env, m='w'):
        file_path = "/tmp/%s" % file_name
        with open(file_path, m) as f:
            f.write(json.dumps(env))
        return file_path

    def read_env(self, file_name,):
        file_path = "/tmp/%s" % file_name
        if not os.path.isfile(file_path) :
            return False
        self.run('cat %s;lsblk' % file_path)
        with open(file_path, "r") as f:
            env = json.loads(f.read())
        os.remove(file_path)
        return env

    def check_options(self, cmd, options):
        #if "_" in str(options):
        #    options = options.replace("_", "-")
        if str(options).startswith('-') :
            options = ' %s' % options
        if os.path.exists(options):
            return True
        cmd="%s --help | grep '%s'" % (cmd, options)
        if self.run(cmd,False,False):
            self._print("FAIL: Could not find %s in help %s" % (options, cmd))
            return False
        return True


class Set_Nvme(Base):
    def __init__(self,):
        self._nvmet_devs = dict()
        self.HOSTNQN = 'libblockdev_nvmeof_hostnqn'
        self.SUBNQN = 'libblockdev_nvmeof_subnqn'


    def _install_package(self, package="nvme-cli nvmetcli"):
        if not linux.is_installed(package):
            linux.install_package(package)
        return True

    def setup_nvme_target(self,dev_paths, subnqn, hostnqn):
        """
        Sets up a new NVMe target loop device (using nvmetcli) on top of the
        :param:`dev_paths` backing block devices.
        :param set dev_paths: set of backing block device paths
        :param str subnqn: Subsystem NQN
        :param str hostnqn: NVMe host NQN
        """

        # modprobe required nvme target modules
        self._install_package()
        ret,out = self.run("modprobe nvmet nvme_loop",True,True)
        if ret != 0:
            raise RuntimeError("Cannot load required NVMe target modules: '%s'" % out)
        self.run("mount -t configfs none /sys/kernel/config")
        # create a JSON file for nvmetcli
        tcli_json_file = "/tmp/nvme_config"
        with open(tcli_json_file,"wt") as tmp:
            namespaces = ",".join(["""
            {{
            "device": {{
                "nguid": "{nguid}",
                "path": "{path}"
            }},
            "enable": 1,
            "nsid": {nsid}
            }}""".format(nguid=uuid.uuid4(), path=dev_path, nsid=i) for i, dev_path in enumerate(dev_paths, start=1)])
            print("namespaces", namespaces)
            _json = """
{
    "hosts": [
    {
        "nqn": "%s"
    }
],
"ports": [
    {
        "addr": {
            "adrfam": "",
            "traddr": "",
            "treq": "not specified",
            "trsvcid": "",
            "trtype": "loop"
        },
        "portid": 1,
        "referrals": [],
        "subsystems": [
            "%s"
        ]
    }
],
"subsystems": [
    {
        "allowed_hosts": [
            "%s"
        ],
        "attr": {
            "allow_any_host": "0"
        },
        "namespaces": [
            %s
        ],
        "nqn": "%s"
        }
    ]
}"""
            print(_json % (hostnqn, subnqn, hostnqn, namespaces, subnqn), type(_json))
            tmp.write(_json % (hostnqn, subnqn, hostnqn, namespaces, subnqn))

        # export the loop device on the target
        ret, out = self.run("nvmetcli restore %s" % tcli_json_file,True)
        #os.unlink(tcli_json_file)
        if ret != 0:
            raise RuntimeError("Error setting up the NVMe target: '%s'" % out)


    def find_nvme_ctrl_devs_for_subnqn(self,subnqn):
        """
        Find NVMe controller devices for the specified subsystem nqn
        :param str subnqn: subsystem nqn
        """

        def _check_subsys(subsys, dev_paths):
            if subsys['SubsystemNQN'] == subnqn:
                for ctrl in subsys['Controllers']:
                    path = os.path.join('/dev/', ctrl['Controller'])
                    try:
                        st = os.lstat(path)
                        # nvme controller node is a character device
                        if stat.S_ISCHR(st.st_mode):
                            dev_paths += [path]
                    except:
                        pass

        ret, out = self.run("nvme list --output-format=json --verbose",True)
        if ret != 0:
            raise RuntimeError("Error getting NVMe list: '%s'" % out)

        decoder = json.JSONDecoder()
        decoded = decoder.decode(out)
        if (not decoded) or ('Devices' not in decoded):
            self._print("FAIL: Could not find 'Devices' in output ")
            return []

        dev_paths = []
        for dev in decoded['Devices']:
            if 'Subsystems' in dev:
                for subsys in dev['Subsystems']:
                    _check_subsys(subsys, dev_paths)
            # nvme-cli 1.x
            if 'SubsystemNQN' in dev:
                 _check_subsys(dev, dev_paths)
        return dev_paths

    def find_nvme_ns_devs_for_subnqn(self, subnqn):
        """
        Find NVMe namespace block devices for the specified subsystem nqn
        :param str subnqn: subsystem nqn
        """

        def _check_namespaces(node, ns_dev_paths):
            for ns in node['Namespaces']:
                path = os.path.join('/dev/', ns['NameSpace'])
                try:
                    st = os.lstat(path)
                    if stat.S_ISBLK(st.st_mode):
                        ns_dev_paths += [path]
                except:
                    pass

        def _check_subsys(subsys, ns_dev_paths):
            if subsys['SubsystemNQN'] == subnqn:
                if 'Namespaces' in subsys:
                    _check_namespaces(subsys, ns_dev_paths)
                # kernel 4.18
                if 'Controllers' in subsys:
                    for ctrl in subsys['Controllers']:
                        if 'Namespaces' in ctrl:
                            _check_namespaces(ctrl, ns_dev_paths)

        ret, out  = self.run_command("nvme list --output-format=json --verbose")
        if ret != 0:
            raise RuntimeError("Error getting NVMe list: %s" % out)

        decoder = json.JSONDecoder()
        decoded = decoder.decode(out)
        if not decoded or 'Devices' not in decoded:
            return []

        ns_dev_paths = []
        for dev in decoded['Devices']:
            # nvme-cli 2.x
            if 'Subsystems' in dev:
                for subsys in dev['Subsystems']:
                    _check_subsys(subsys, ns_dev_paths)
            # nvme-cli 1.x
            if 'SubsystemNQN' in dev:
                _check_subsys(dev, ns_dev_paths)

        return ns_dev_paths







    def create_nvmet_device(self, dev_path):
        """
        Creates a new NVMe target loop device (using nvmetcli) on top of the
        :param:`dev_path` backing block device and initiates a connection to it.
        :param str dev_path: backing block device path
        :returns: path of the NVMe controller device (e.g. "/dev/nvme0")
        :rtype: str
        """

        self.setup_nvme_target(dev_path, self.SUBNQN, self.HOSTNQN)

        # connect initiator to the newly created target
        ret, out = self.run("nvme connect --transport=loop --hostnqn=%s --nqn=%s" % (self.HOSTNQN, self.SUBNQN),True)
        if ret != 0:
            raise RuntimeError("Error connecting to the NVMe target: '%s'" % out)

        nvme_devs = self.find_nvme_ctrl_devs_for_subnqn(self.SUBNQN)
        if len(nvme_devs) != 1:
            raise RuntimeError("Error looking up block device for the '%s' nqn" % self.SUBNQN)

        self._nvmet_devs[nvme_devs[0]] = (self.SUBNQN, dev_path)
        return self._nvmet_devs



    def delete_nvmet_device(self, nvme_dev):
        """
        Logout and tear down previously created NVMe target device.
        :param str nvme_dev: path of the NVMe device to delete
        """
        if nvme_dev in self._nvmet_devs:
            subnqn, dev_path = self._nvmet_devs[nvme_dev]

            # disconnect the initiator
            ret, out = self.run("nvme disconnect --nqn=%s" % subnqn,True)
            if ret != 0:
                raise RuntimeError("Error disconnecting the '%s' nqn: '%s'" % (subnqn, out))

            # clear the target
            return self.teardown_nvme_target()
        else:
            self._print("FAIL: Could not find the device %s" % nvme_dev)
            return

    def teardown_nvme_target(self,):
        """
        Tear down any previously set up kernel nvme target.
        """
        ret, out = self.run("nvmetcli clear", True)
        if ret != 0:
            raise RuntimeError("Error clearing the NVMe target: '%s'" % out)
        return True






class Blockdev(Set_Nvme):
    def __init__(self, ):
        bd_plugins = { "lvm": bd.Plugin.LVM,
               "crypto": bd.Plugin.CRYPTO,
               "dm": bd.Plugin.DM,
               "loop": bd.Plugin.LOOP,
               "swap": bd.Plugin.SWAP,
               "mdraid": bd.Plugin.MDRAID,
               "part": bd.Plugin.PART,
               "fs": bd.Plugin.FS,
               "kbd": bd.Plugin.KBD,
               "nvdimm": bd.Plugin.NVDIMM,
               #"nvme": bd.Plugin.NVME,
            }

        self.REQUESTED_PLUGIN_NAMES = bd_plugins
        ret = []
        for name in self.REQUESTED_PLUGIN_NAMES:
            plugin = bd.PluginSpec()
            plugin.name = bd_plugins[name.lower()]
            ret.append(plugin)
        bd.switch_init_checks(False)
        if not bd.is_initialized():
            bd.init(ret, None)
        else:
            bd.reinit(ret, True, None)
        bd.switch_init_checks(True)
        super().__init__()


    def init_disk(self, disk):
        requested_plugins = bd.plugin_specs_from_names(self.REQUESTED_PLUGIN_NAMES)
        bd.switch_init_checks(False)

        if not bd.is_initialized():
            bd.init(requested_plugins, None)
        else:
            bd.reinit(requested_plugins, True, None)
        bd.switch_init_checks(True)

        try:
            bd.fs.wipe(disk, True)
        except bd.FSError as e:
            # wipe() fails when the device is already empty, but that's okay for us
            if str(e).startswith("No signature"):
                pass
            else:
                # some other error is a real one, though
                raise

    def add_fs(self, device, fs = linux.get_default_fs(), **kwargs):
        if fs == "xfs" :
            self.fs = "xfs"
            return bd.fs_xfs_mkfs(device, [bd.ExtraArg.new("-f", "")])
        self.fs= "ext4"
        return bd.fs_ext4_mkfs(device)

    def remove_fs(self, disk, clean=False):
        if not clean :
            return
        return self.run("wipefs -a %s" % disk)

    def add_mount(self, disk,):
        tmp = tempfile.mkdtemp(prefix="libblockdev.", suffix="mount_test")
        if not bd.fs_mount(disk, tmp, self.fs):
            self._print("FAIL: Could not mount the disk %s" % disk)
            return
        return tmp

    def remove_mount(self, disk):
        tmp = bd.fs_get_mountpoint(disk)
        self._print("INFO: get the mount %s" % tmp)
        if not os.path.ismount(tmp) :
            return True
        return bd.fs_unmount(disk)


    def _get_nvdimm_info(self):
        #  grubby --args="memmap=4G\!6G" --update-kernel=ALL (mem from 6G to 10G, size is 4G)
        # reboot
        linux.install_package("ndctl")
        ret, out = self.run("ndctl list", True, True)
        if ret != 0 or not out:
            ret, out = self.run("ndctl enable-namespace all",True, True)
            if not out or 'No such device' in out:
                return
        decoder = json.JSONDecoder()
        decoded = decoder.decode(out)
        if not decoded :
            self._print("FAIL: The system don't have nvdimm")
            return
        # get the first one
        self.nvdimm_info = decoded[0]
        return self.nvdimm_info

    def add_nvdimm(self,):
        ndctl_info = self._get_nvdimm_info()
        if not ndctl_info :
            self._print("FAIL: the system don't have nvdimm")
            return
        bd_info = bd.nvdimm_namespace_info(ndctl_info["dev"])
        if not bd.nvdimm_namespace_enable(ndctl_info["dev"]):
            self._print("FAIL: Could not enable the namespace")
            return
        return "/dev/%s" % bd_info.blockdev

    def remove_nvdimm(self, ns):
        if not bd.nvdimm_namespace_disable(ns):
            self._print("FAIL: Could not disable dev namespace %s" % ns)
            return
        return True



    def add_swap(self, disk, vg_name="TEST_VG", lv_name="TEST_LV"):
        label='BlockDevSwap'
        new_disk = self.add_lvm(disk, vg_name, lv_name)
        if not bd.swap_mkswap(new_disk):
            self._print("FAIL: Could not make swap with disk %s" % disk)
            return
        if not bd.swap_set_label(new_disk, label):
            self._print("FAIL: Could not set label %s" % label)
        if not bd.swap_swapon(new_disk, -1):
            self._print("FAIL: Could not make swap on disk %s" % disk)
            return
        if not bd.swap_swapstatus(new_disk):
            self._print("FAIL: COuld not get swap status %s" % disk)
            return
        return True

    def remove_swap(self, disk, vg_name="TEST_VG", lv_name="TEST_LV"):
        if not bd.swap_swapoff(disk):
            self._print("FAIL: Could not swapoff with disk %s" % disk)
            return
        if not self.remove_lvm(disk, vg_name, lv_name):
            self._print("FAIL: Could not remove lvm from swap")
            return
        return True

    def add_dm(self, disk, name, size=3) :
        if not bd.dm_create_linear(name, disk, int(size) * 1024**2, None):
            self._print("FAIL: Could not create dm %s" % name)
            return
        return "/dev/mapper/%s" % name

    def remove_dm(self, name ,disk ):
        if not bd.dm_remove(name):
            self._print("FAIL: Could not remove dm %s" % name)
        self.run("dd if=/dev/zero of=%s bs=1M count=10" % disk,False,True)
        return True

    def add_bcache(self, disk=[]):
        if not linux.install_package("make-bcache"):
            self._print("FAIL: Could not find make-bcache")
            return
        if  len(disk) < 2 :
            self._print("FAIL: need two disks")
            return
        succ, dev = bd.kbd_bcache_create(*disk)
        if not succ :
            self._print("FAIL: Could not create bcache device with disk %s" % disk)
            return
        self._wait_for_bcache_setup(dev)
        return dev


    def _wait_for_bcache_setup(self, bcache_dev):
        i = 0
        cache_dir = "/sys/block/%s/bcache/cache" % bcache_dev
        while not os.access(cache_dir, os.R_OK):
            time.sleep(1)
            i += 1
            if i >= 30:
                print("WARNING: Giving up waiting for bcache setup!!!")
                break

    def remove_bcache(self, device, disk,):
        if not bd.kbd_bcache_destroy(device):
            self._print("FAIL: Could not destroy bcache device %s" % device)
            return
        if len(disk) < 2 :
            self._print("FAIL: need all bcache disk")
            return
        for i in disk :
            self.run("wipefs -a %s" % i)
        return True

    def load_module(self, m):
        ret = self.run("lsmod | grep %s" % m)
        if not ret :
            linux.unload_module(m)
        if not linux.load_module(m):
            self._print("FAIL: Could not module %s" % m)
            return
        return True



    def add_zram(self):
        #self.load_module("zram")
        if not bd.kbd_zram_create_devices(1, [500 * 1024**2,], None):
            self._print("FAIL: Could not create zram device")
            return
        if not bd.kbd_zram_get_stats("/dev/zram0"):
            return
        return "/dev/zram0"


    def remove_zram(self, device):
        self._print("INFO: will remove zram %s " % device)
        self.load_module("zram")
        linux.sleep(5)
        return bd.kbd_zram_destroy_devices()


    def add_part(self, disk, size=5):
        if not isinstance(size,int):
            self._print("FAIL: input wrong size type, please input int type, default is G")
            return
        self.init_disk(disk)
        self._print("INFO: will add a part table")
        bd.part.create_table(disk, bd.PartTableType.MSDOS, False)
        ps=bd.part.create_part(disk, bd.PartTypeReq.NORMAL, 2048*512, int(size) * 1024**3, bd.PartAlign.OPTIMAL )
        if not ps.path :
            self._print("FAIL: can not get part")
            return
        self._print("INFO: have create %s" % ps.path)
        return ps.path

    def remove_part(self, disk, part):
        return bd.part.delete_part(disk, part)

    def add_lvm_vg(self, disk, vg_name):
        #if isinstance(disk, list):
        #    for d in disk:
        #        if not bd.lvm_pvcreate(d):
        #             self._print("FAIL: Could not create pv on disk %s" % d)
        #             return
        #    vg_disk = disk
        #else:
        #    print("the disk is %s" % disk)
        #    vg_disk = [disk,]
        #    if not bd.lvm_pvcreate(disk):
        #        self._print("FAIL: Could not create pv on disk %s" % disk)
        #        return

        if isinstance(disk, list):
            str_disk = " ".join(disk)
            vg_disk = disk
        else:
            vg_disk = [disk,]
            str_disk = disk
        ret, out = self.run("pvcreate %s -y " % str_disk,True)
        if ret :
            self._print("FAIL: Could not create PV on disk %s, error is %s" % (str_disk, out))
            return
        if not bd.lvm_vgcreate(vg_name, vg_disk, 0, None):
            self._print("FAIL: Could not create vg on disk %s" % vg_disk)
            self.run("pvremove -y %s" % str_disk,)
            return
        return (vg_name,vg_disk,str_disk)

    def add_lvm(self, disk, vg_name, lv_name, size=3):
        vg_info = self.add_lvm_vg(disk, vg_name)
        if not vg_info :
            return
        ret = bd.lvm_lvcreate(vg_info[0], lv_name, int(size) * 1024**3, None, vg_info[1], None)
        if not ret :
            self._print("FAI:: Could not create lv size %sG on disk %s" % (size , vg_info))
            bd.lvm_vgremove(vg_name)
            self.run("pvremove -y %s" % vg_info[2])
            return
        return "/dev/mapper/%s-%s" % (vg_info[0], lv_name)


    def add_snap(self, disk, vg_name, lv_name, snap_name, size=3, ) :
        if not self.add_lvm(disk, vg_name, lv_name, size=size):
            self._print("FAIL: COuld not creat lvm for snap %s" % disk)
            return
        if not bd.lvm_lvsnapshotcreate(vg_name, lv_name, snap_name, 3 * 1024**3, None):
            self._print("FAIL: Could not create snapshot %s" % snap_name)
            self.remove_lvm(disk, vg_name, lv_name)
            return
        return "/dev/mapper/%s-%s" % (vg_name, snap_name)



    def add_dmraid(self, disk, vg_name, lv_name, size=3, raid_level="raid1"):
        # raid_level striped,mirror,
        if not isinstance(disk, list):
            self._print("FAIL: need a disk list")
            return
        if len(disk) < 2 :
            self._print("FAIL: need moren 2 disks")
            return
        vg_info = self.add_lvm_vg(disk, vg_name)
        if not vg_info :
            return
        if not bd.lvm_lvcreate(vg_name,  lv_name, int(size) * 1024**3, raid_level, vg_info[1], None):
            self._print("FAIL: Could not create lvm %s" % raid_level)
            return
        return "/dev/mapper/%s-%s" % (vg_info[0], lv_name)



    def add_vdo(self, disk, vg_name, lv_name, size=3):
        if self.run("lvcreate --type vdo -h",False, False,):
            self._print("FAIL: COuld not add vdo with lvcreate")
            return
        if not self.load_module("kvdo"):
            self._print("FAIL: Could not load kvdo module")
            return
        vg_info = self.add_lvm_vg(disk, vg_name)
        if not vg_info :
            return
        if not bd.lvm_vdo_pool_create(vg_name, lv_name, "vdoPool", int(size) * 1024**3, 40 * 1024**3):
            self._print("FAIL: Could not create vdo")
        #   return
        #cmd="lvcreate --type vdo -n %s -L %sG -V 100G %s/vdopool -y" % (lv_name, size, vg_info[0])
        #ret, out=self.run(cmd,True)
        #if ret :
        #    self._print("FAIL: run cmd %s failed and error %s" % (cmd, out))
            bd.lvm_vgremove(vg_name,)
            self.run("pvremove -y %s" % vg_info[2])
            return
        return "/dev/mapper/%s-%s" % (vg_name, lv_name)


    def remove_lvm(self, disk, vg_name, lv_name):
        err = 0
        if not bd.lvm_lvremove(vg_name, lv_name,True,):
            self._print("FAIL: Could not remove lvm %s-%s" % (vg_name,lv_name))
            err += 1
        if not bd.lvm_vgremove(vg_name,):
            self._print("FAIL: Could not remove vg %s" % vg_name)
            err += 1
        if isinstance(disk, list):
            str_disk = " ".join(disk)
        else:
            str_disk = disk
        if self.run("pvremove -y %s" % str_disk):
            self._print("FAIL: Could not remove pv disk %s " % str_disk)
            err += 1
        if err :
            return False
        return True


    @contextmanager
    def wait_for_action(self,action_name):
        try:
            yield
        finally:
            time.sleep(2)
            action = True
            while action:
                with open("/proc/mdstat", "r") as f:
                    action = action_name in f.read()
                if action:
                    print("Sleeping")
                    time.sleep(1)


    def add_raid(self,raid_name, raid_mem, raid_level,**kwrags):
        if len(raid_mem) < 2:
            self._print("FAIL: need two disks")
            return
        with self.wait_for_action("resync"):
            succ = bd.md_create(raid_name, raid_level,raid_mem, **kwrags)
        if not succ :
            self._print("FAIL: Could not create MD raid with %s" % raid_name)
            return False
        self._print("INFO: create MD raid successful with %s" % raid_name)
        print(bd.md_detail(raid_name))
        return "/dev/md/%s" % raid_name

    def remove_raid(self,raid_name, raid_mem):
        for disk in raid_mem :
            if not bd.md_examine(disk):
                return False
        if not bd.md_deactivate(raid_name):
            self._print("FAIL: Could not deactive the raid %s" % raid_name)
            return False
        if not isinstance(raid_mem, list):
            self._print("FAIL: please input list for raid_mem")
            return False
        for disk in raid_mem:
            if bd.md_destroy(disk):
                self._print("INFO: destroy raid mem %s" % disk)
            else:
                self._print("FAIL: destroy raid mem %s" % disk)
        return True

    @classmethod
    def create_sparse_file(cls,path, size):
        """ Create a sparse file.

        :param str path: the full path to the file
        :param size: the size of the file (in bytes)
        :returns: None
        """
        fd = os.open(path, os.O_WRONLY|os.O_CREAT|os.O_TRUNC)
        os.ftruncate(fd, size)
        os.close(fd)

    @classmethod
    def create_sparse_tempfile(cls,name, size):
        """ Create a temporary sparse file.

        :param str name: suffix for filename
        :param size: the file size (in bytes)
        :returns: the path to the newly created file
        """
        (fd, path) = tempfile.mkstemp(prefix="bd.", suffix="-%s" % name)
        os.close(fd)
        cls.create_sparse_file(path, size)
        return path



    def add_loop(self,file_name="loop_test", size=5):
        dev_file = self.create_sparse_tempfile(file_name, int(size) * 1024**3)
        print(dev_file)
        succ, loop_name = bd.loop_setup(dev_file)
        if not succ :
            self._print("FAIl: Could not create loop device")
            return
        return loop_name

    def remove_loop(self, loop_name):
        return bd.loop_teardown(loop_name)

    def add_nvme(self, num=1):
        loop_dev=[]
        for i in range(num):
            loop_dev += [ "/dev/%s" %  self.add_loop("loop_file%s" % i, size=5)]
        self.nvme_info = self.create_nvmet_device(loop_dev)
        if not self.nvme_info :
            self._print("FAIL: Could not set nvme target with %s" % loop_dev)
            return
        return self.find_nvme_ns_devs_for_subnqn(self.SUBNQN)

    def remove_nvme(self, nvme_info):
        if not nvme_info :
            self._print("FAIL: Could not remove nvme target")
            nvme_info = self.nvme_info
        for i in list(nvme_info.keys()):
            if not self.delete_nvmet_device(i):
                self._print("FAIL: Could not delete nvme device")
                return
            for l in nvme_info[i][1] :
                self.remove_loop(l)
        return True





class Luks(Blockdev):
    def __init__(self,):
        self.cmd = "cryptsetup"
        self.passwd = "passwdpasswd"
        self.stratis = stratis.Stratis()
        self.vg_name = "TEST_VG"
        self.lv_name = "TEST_LV"
        self.raid_name= "test_raid"
        self.raid_level = "raid1"
        self.pool_name = "test_pool"
        self.fs_name = "test_fs"
        self.dm_name = "test_dm"
        self.snap_name = "TEST_SNAP"
        Blockdev.__init__(self,)
        self.target_type =  ["loop",]
        #self.target_type =  ["nvme","lvm", "part","raid","zram","loop","stratis",]
        #skip ["bcache","snap","vdo", "dm"],
        #need add paramter to kernel for nvdimm
        #snap skip from developer
        for p in ["cryptsetup","integritysetup", "keyutils", "coreutils",
        "util-linux","vim-common",]:
            if not linux.is_installed(p):
                if not linux.install_package(p, check=False):
                    self._print("FAIL: Could not install %s" % p)

    def get_free_disk(self, num=1,):
        free_disk = []
        scsi_free_disk = scsi.get_free_disks()
        if scsi_free_disk :
            for i in list(scsi_free_disk.keys()):
                if not scsi.size_of_disk(i):
                    scsi_free_disk.pop(i)
                    continue
                self.run("dd if=/dev/zero of=/dev/%s bs=1M count=10"  % i, False,False)
                self.run("wipefs -a /dev/%s" % i,False,False)
        if scsi_free_disk :
            free_disk = [ "/dev/%s" % i for i in scsi_free_disk.keys()  ]
        if len(free_disk) < int(num) :
            if loop.get_loopdev() :
                for l in loop.get_loopdev():
                    self.remove_loop(l)
            for i in range(0, int(num) - len(free_disk)):
                self._print("INFO: will create loop device loop%s" % i)
                free_disk.append("/dev/%s" % self.add_loop("loop%s" % i, 5))
        self._print("INFO: free disk %s" % free_disk)
        return free_disk[0:num]

    def add_stratis(self, name, device, fs_name):
        if isinstance(device,str):
            device = device.split()
        if self.stratis.pool_create(name, device):
            self._print("FAIL: Could not create straits pool")
            return
        if self.stratis.fs_create(name, fs_name, fs_size='3GiB'):
            self._print("FAIL: Could not create straits pool fs")
            return
        return "/dev/stratis/%s/%s" % (name,fs_name)

    def remove_stratis(self, pool_name, fs_name):
        if self.stratis.fs_destroy(pool_name, fs_name):
            self._print("FAIL: Could not remove straits fs %s" % fs_name)
        if self.stratis.pool_destroy(pool_name):
            self._print("FAIL: Could not remove stratis %s " % pool_name)
        return True


    def make_test_target(self,l_type="",num=2,):
        mpaths = mp.get_free_mpaths(
        exclude_boot_device=True, exclude_lvm_device=True)
        if mpaths:
            mp_key = list(mpaths.keys())
            print("the mp key %s" % mp_key)
            disks_list = ["/dev/mapper/%s" % d for d in mp_key]
        else:
            disks_list=self.get_free_disk(num=num)
            [self.init_disk(i) for i in disks_list ]

        self._print("INFO: setup the storage %s " % l_type)
        self._print("INFO: free disk is %s" % disks_list)

        self.device_type = l_type

        if l_type == "part":
            test_disk = disks_list.pop()
            partition=self.add_part(test_disk ,3)
            if partition :
                self.write_env("part",(test_disk, partition))
            return partition
        if l_type == "dmraid":
            test_disk = disks_list[0:2]
            dev = self.add_dmraid(test_disk, self.vg_name, self.lv_name, size=3, raid_level="raid1")
            if dev :
                self.write_env("lvm",(test_disk, self.vg_name, self.lv_name))
            return dev
        if l_type == "snap" :
            test_disk = disks_list.pop()
            dev = self.add_snap(test_disk, self.vg_name, self.lv_name, self.snap_name, size=3,)
            if dev :
                self.write_env("lvm",(test_disk, self.vg_name, self.snap_name))
            return dev
        if l_type == "lvm":
            test_disk = disks_list.pop()
            dev = self.add_lvm(test_disk, self.vg_name, self.lv_name, size=3)
            if dev :
                self.write_env("lvm",(test_disk, self.vg_name, self.lv_name))
            return dev
        if l_type == "vdo":
            test_disk = disks_list.pop()
            dev = self.add_vdo(test_disk, self.vg_name, self.lv_name, size=3)
            if dev :
                self.write_env("lvm",(test_disk, self.vg_name,self.lv_name))
            return dev
        if l_type == "raid" :
            self.raid_mem = disks_list[0:2]
            dev = self.add_raid(self.raid_name, self.raid_mem, self.raid_level, size="3G")
            if dev :
                self.write_env("raid",(self.raid_name, self.raid_mem))
            return dev
        if l_type == "stratis" :
            test_disk = disks_list.pop()
            dev = self.add_stratis(self.pool_name, test_disk, self.fs_name)
            if dev :
                self.write_env("stratis",(self.pool_name, self.fs_name))
            return dev
        if l_type == "dm" :
            test_disk = disks_list.pop()
            dev = self.add_dm(test_disk, self.dm_name)
            if dev :
                self.write_env("dm",(self.dm_name, test_disk))
            return dev
        if l_type == "nvme":
            dev = self.add_nvme(num=1)[0]
            if dev :
                self.write_env("nvme", self.nvme_info)
            return dev
        if l_type == "nvdimm":
            dev = self.add_nvdimm()
            if dev :
                self.write_env("nvdimm",dev )
            return dev
        if l_type == "zram" :
            dev = self.add_zram()
            if dev :
                self.write_env("zram", (dev,))
            return dev
        if l_type == "swap" :
            test_disk = disks_list.pop()
            dev = self.add_swap(test_disk, self.vg_name, self.lv_name)
            if dev :
                self.write_env("swap",(test_disk, self.vg_name, self.lv_name))
            return dev
        if l_type == "bcache" :
            test_disks = disks_list[0:2]
            dev = self.add_bcache(test_disks)
            if dev :
                self.write_env("bcache",(dev,  test_disks))
            return dev
        if l_type == "loop":
            dev = self.add_loop()
            if dev :
                self.write_env("loop",(dev,))
            return "/dev/%s" % dev


    def force_clean_up(self):
        if not self.run("lsblk |grep '/tmp/'"):
            self.run("umount -a")
        for i in range(4):
            ret, out = self.run("lsblk |grep crypt |head -1", True, False)
            while ret == 0 and out:
                self._print("INFO:the crypt out is [%s]" % out)
                t_name1 = re.match(r'(\s?)([a-z]+.\d?)(\s+\S+){4,}', out)
                t_name2 = re.match(r'(\s?)(([a-z].\d+)-([a-z]*.\d?))(\s+\S+){4,}', out)
                [self.run("cryptsetup close %s" % name.group(2))
                 for name in [t_name1, t_name2] if name]
                ret, out = self.run("lsblk |grep crypt |head -1", True, False)
                self._print("INFO: the t_name1 is %s, t_name2 is %s, ret %s, out %s" %(t_name1,t_name2,ret,out))
                if not ret:
                    ret,device=self.run("lsblk -P |grep crypt | awk '{print $1}' |tail -1 \
                            | awk -F '=' '{print $2}'",True,False)
                    if device :
                        self.run("cryptsetup close %s" % device)

        #keys = ["nvme","vdo","lvm", "part","raid","stratis","dm"]
        keys = self.target_type
        for key in keys:
            if key in ["vdo", "lvm", "dmraid", "snap"]:
                key = "lvm"
            remove_function = "remove_%s" % key
            _env = self.read_env(key)
            if not _env :
                continue
            self._print("INFO: will run %s" % remove_function)
            if hasattr(self,remove_function):
                if isinstance(_env, dict):
                    getattr(self, remove_function)(_env,)
                else:
                    getattr(self, remove_function)(*_env,)

        if loop.get_loopdev():
            for device in loop.get_loopdev():
                if device:
                    loop.delete_loopdev(device)
        return True



    #pbkdf = BlockDev.CryptoLUKSPBKDF(type="pbkdf2")
    #extra = BlockDev.CryptoLUKSExtra(pbkdf=pbkdf)
    #pbkdf = BlockDev.CryptoLUKSPBKDF(type="argon2id", max_memory_kb=100*1024, iterations=10, parallel_threads=1)
    #extra = BlockDev.CryptoLUKSExtra(pbkdf=pbkdf)
    #pbkdf = BlockDev.CryptoLUKSPBKDF(max_memory_kb=100*1024)
    #extra = BlockDev.CryptoLUKSExtra(pbkdf=pbkdf)

    # aes-xts-plain64 , aes-xts: key size should default to 512
    # aes-cbc-essiv:sha256 ,  aes-cbc: key size should default to 256

    def add_crypt(self, disk, cipher="aes-xts-plain64", key_size=0, passphrase="passwdpasswd", key_file=None, min_entropy=0, luks_version=bd.CryptoLUKSVersion.LUKS2, extra=None):
        self._print("INFO: will crypt device %s" % disk)
        linux.sleep(5)
        if not bd.crypto_luks_format(disk, cipher=cipher, key_size=key_size, passphrase=passphrase,
                key_file=key_file, min_entropy=min_entropy, luks_version=luks_version, extra=extra):
            self._print("FAIL: Could not format disk %s" % disk)
            return False
        return disk

    def open_crypt(self, disk, name="libblockdevTestLUKS", passphrase="redhat redhat", key_file=None, read_only=False):
        if not bd.crypto_luks_open(disk, name=name, passphrase=passphrase, key_file=key_file, read_only=read_only):
            return
        return name

    def remove_crypt(self,name):
        self._print("INFO: remove crypt device")
        return bd.crypto_luks_close(name)

    def resize_crypt(self,name, size=0, passphrase=None, key_file=None ):
        return bd.crypto_luks_resize(name, size, passphrase, key_file)

    def luks_info(self, name):
        """
        name : crypt device name
        return {'version': 'LUKS2', 'backing_device': '/dev/md127', 'cipher': 'twofish', 'mode': 'xts-plain64', 'sector_size': 4096, 'uuid': 'ad4fde4b-fc47-4fd5-a4ae-c465858faaf4'}
        """
        dict_info = {}
        info = bd.crypto_luks_info(name)
        dict_info["version"] = info.version.value_name.split("_")[-1]
        dict_info["backing_device"] = info.backing_device
        dict_info["cipher"] = info.cipher
        dict_info["mode"] = info.mode
        dict_info["sector_size"] = info.sector_size
        dict_info["uuid"] = info.uuid
        return dict_info

    def luks_header(self):
        header = "/tmp/testheader%s" % self.range_str(3)
        if self.run("truncate -s 4096 %s" % header, False,False) :
            self._print("FAIL: Create headerfile fialed")
            return
        return header


    def luks_keyfile(self, num):
        #if num <= 50:
        #    handle, self.keyfile = tempfile.mkstemp(prefix="libblockdev_test_keyfile", text=False)
        #    os.write(handle, self.range_str(num).encode(encoding="utf-8"))
        #    os.close(handle)
        #else:
        range_str=''
        tmp_file = "/tmp/testfile%s" % self.range_str(3)
        for i in  range(num):
            range_str += random.sample(string.ascii_letters + string.digits, 1)[0]
        with open(tmp_file,"wb") as f:
            f.write(range_str.encode('utf-8'))
        #self.keyfile = tmp_file
        return tmp_file


    #  echo -n stuff | keyctl padd user mykey @u
    #                  keyctl add user mykey stuff @u
    # user
    # test_key = key_des,
    # test_data = new_pass
    # TEST_KEYRING=$(keyctl newring $TEST_KEYRING_NAME "@u"
    def load_keying(self, new_pass, key_des ):
        self._print("INFO: load the passphrase in user keying")
        ret, out = linux.run('echo -n %s | keyctl padd user %s @u' % (new_pass, key_des), True, True)
        if ret :
            self._print("FAIL: Could not add key to keying")
            return False
        self._print("INFO: keyctl ret is [%s] ,out is [%s]" % (ret, out))
        self._print("INFO: add key to keyctl OK")
        return True

    def load_key(self, option):
        cmd="keyctl add %s" % option
        if self.run(cmd):
            self._print("FAIL: Kernel keyring service is useless on this system, test skipped, cmd: %s" % cmd)
            return False
        return True

    def test_and_prepare_keyring(self, test_keyring_name='keyring_name'):
        if self.run("which keyctl"):
            self._print("FAIL: Cannot find keyctl, test skipped")
            return False
        if self.run('keyctl list "@s"'):
            self._print("FAIL: Current session keyring is unreachable, test skipped")
            return False
        cmd='keyctl newring %s "@u"' % test_keyring_name
        ret, self.test_keyring = self.run(cmd, True)
        if ret or (not self.test_keyring):
            self._print("FAIL:Could not create keyring in user keyring")
            return False
        cmd='keyctl search "@s" keyring %s' % self.test_keyring
        ret = self.run(cmd,True)
        if ret :
            self.run('keyctl link "@u" "@s"')
        return self.load_key('user test_key test_data %s ' % self.test_keyring)


    def dm_crypt_keyring_support(self,):
        ret, crypt_version = self.run('dmsetup targets | grep crypt | cut -f2 -dv', True)
        if ret :
            self._print("FAIL: Could not get dm-crypt version.")
            return False
        dm_crypt_version = crypt_version.split('.')
        ver_maj =  int(dm_crypt_version[0])
        ver_min =  int(dm_crypt_version[1])
        ver_ptc =  int(dm_crypt_version[2])
        if not os.path.exists('/proc/sys/kernel/keys') :
            return False
        if ver_maj > 1 :
            return True
        if (ver_maj == 1) and (ver_min > 18):
            return True
        if (ver_maj == 1) and (ver_min == 18) and (ver_ptc > 1):
            return True
        return False

    def dm_crypt_keyring_new_kernel(self,):
        ret, kernel_version = self.run('uname -r', True)
        kernel_v = kernel_version.split('.')
        ker_maj = int(kernel_v[0])
        ker_min = int(kernel_v[1])
        if  ker_maj >= 5 :
            return True
        if (ker_maj == 4) and (ker_min >=15 ):
            return True
        return False



    def dm_crypt_sector_size_support(self,):
        ret, crypt_version = self.run('dmsetup targets | grep crypt | cut -f2 -dv', True)
        if ret :
            self._print("FAIL: Could not get dm-crypt version.")
            return False
        dm_crypt_version = crypt_version.split('.')
        ver_maj =  int(dm_crypt_version[0])
        ver_min =  int(dm_crypt_version[1])
        ver_ptc =  int(dm_crypt_version[2])
        if (ver_min >= 17) or (ver_min == 14 and (ver_ptc > 5)) or ver_maj >1:
            return True
        return False


    def luks_dump(self, device, option="--dump-json-metadata", grep='', **kw ):
        param = ""
        if kw :
            for k in kw:
                param += " --%s %s" % (k, kw[k])
        cmd  = "%s luksDump %s %s %s" % (self.cmd, option, param, device,)
        if grep :
            cmd += " | grep -q '%s'" % grep
        ret, out = self.run(cmd,True,True)
        if ret :
            self._print("FAIL: Couls not run the cmd %s" % cmd)
            return
        if option :
            dump_info = json.loads(out)
        else:
            dump_info = out
        return dump_info


    def run_io(self, device):
        if not self.add_fs(device):
            self._print("FAIL: Could not add fs to device %s" % device)
            return
        test_dir = self.add_mount(device)
        if test_dir :
            self.run("lsblk")
            self.run_fio(test_dir + "/test.dd", size="1g", time=60)
            self.remove_mount(device)
            self.remove_fs(device, False)
        else:
            self._print("FAIL: Could not mount the device %s" % device)
            return
        self.run("lsblk")
        return True


    #def crypto_keyring_add_key(self, key_desc, key)
    #def crypto_luks_open_keyring(self,):
    #def crypto_luks_add_key(self,device, pass_=None, key_file=None, npass=None, nkey_file=None):
    # pass_ : paswd
    # npass : new passwd
    #def crypto_luks_remove_key(self, device, pass_=None, key_file=None)
    #def crypto_luks_change_key(self, devive, PASSWD, PASSWD2)
    #def crypto_device_is_luks(self, device):
    #def crypto_luks_status("/dev/mapper/test_luks"):
    #def crypto_luks_uuid(self, device):
    #def crypto_luks_resume(device, passphrase=None, key_file=None ):
    # "libblockdevTestLUKS", PASSWD, None
    #def crypto_luks_suspend("/dev/mapper/libblockdevTestLUKS"):
    #def crypto_luks_kill_slot(self.loop_dev, 1)):
    #def crypto_luks_info(device):

    #def crypto_integrity_info(name/device):
    #def crypto_luks_token_info(device): removed

    # def crypto_integrity_format(device, algorithm=None, wipe=True, key_data=None, extra=None):
    # def crypto_integrity_open(device, name, algorithm, key_data=None, flags=0, extra=None):

    def luks_add_key_db(self, device, old_key=None, new_key=None, keyfile=None, new_keyfile=None):
        return bd.crypto_luks_add_key(device, old_key, keyfile, new_key, new_keyfile)

    def luks_remove_key_db(self, device, remove_key=None, remove_keyfile=None):
        return bd.crypto_luks_remove_key(device, remove_key, remove_keyfile)

    def luks_status(self, name, grep=''):
        s_dict={}
        cmd = "cryptsetup -v status %s" % name
        if grep :
            cmd += " | grep '%s'" % grep
        ret, out = self.run(cmd, return_output=True)
        if ret and not out:
            return s_dict
        for line in out.split("\n"):
            if ":" in line:
                l_list=line.split(":")
                s_dict[l_list[0].strip()] = l_list[1].strip()
        return s_dict



    def luks_add_key(self, device, old_key=None, new_key=None, spec=("-q",),  return_code=0, **cmd_ops ):
        param = ""
        spec_args=""
        for key in cmd_ops.keys():
            if cmd_ops[key]:
                param += "--%s '%s' " % (key, cmd_ops[key])
        if "_" in param:
            param = param.replace("_", "-")

        for i in spec :
            spec_args += " %s " % i

        key_cmd=""
        if all([old_key, new_key]) :
            key_cmd = "echo -e \"%s\n%s\n\" " % (old_key, new_key)
        elif any([old_key, new_key]):
            for k in [old_key, new_key]:
                if not k :
                    continue
                key_cmd = "echo %s" %  k
        if key_cmd :
            key_cmd += " | "
        #if new_key :
        #    key_cmd= "echo -e \"%s\n%s\n\" " % (old_key, new_key)
        #else:
        #    key_cmd= "echo -e \"%s\n%s\n\" " % (old_key, new_key)
        cmd=" %s %s luksAddKey %s %s %s" % (key_cmd, self.cmd, param, device, spec_args)
        ret, out = self.run(cmd, True, True)
        if ret != return_code:
            self._print("FAIL: the ret %s, out is >%s<,  set return_code %s , cmd >%s<" % (ret, out, return_code, cmd))
            return False
        return True

    def get_fips(self,):
        ret, fips_mode = self.run('cat /proc/sys/crypto/fips_enabled', True)
        if (ret == 0) and fips_mode :
            if os.path.exists('/etc/system-fips'):
                return True
        return False

    def debug_cmd(self, cmd):
        cmd += " --debug "
        ret, out = self.run(cmd, True,)
        if ret == 0 :
            self._print("INFO: test pass with the cmd %s after add debug" % cmd)
            return True
        return False



    def run_cmd(self, device="",action="",dmname="",set_passwd=True, spec=("-q",),
            return_code=0, grep="", ignore_failed="", **cmd_ops):
        """
        spce = ("-q","--encrypt", "--init-only")
        """
        param = ""
        out=''
        spec_args=""
        miss_key=[]
        status = True
        for key in cmd_ops.keys():
            values = str(cmd_ops[key])
            if "_" in key:
                key = key.replace("_", "-")
            if "_" in values:
                values = values.replace("_", "-")
            if values:
                if self.check_options(self.cmd, key):
                    param += "--%s '%s' " % (key, values)
                else:
                    status = False
                    miss_key.append(key)
        if "_" in param:
            param = param.replace("_", "-")
        for i in spec :
            if str(i).startswith('-') :
                if self.check_options(self.cmd, i):
                    spec_args += " %s " % str(i)
                else:
                    status = False
                    miss_key.append(i)
            else:
                spec_args += " %s " % str(i)
        if miss_key :
            self._print("FAIL: Could not find options %s in help " % miss_key)


        cmd = "%s %s %s %s %s %s" % (self.cmd, param, action, device,dmname, spec_args)
        if grep :
            cmd += " | grep -q '%s' " % grep
        if set_passwd :
            if set_passwd == True :
                cmd = "echo %s | %s" % (self.passwd, cmd)
            else:
                cmd = "echo %s | %s" % (set_passwd, cmd)
        if status :
            ret, out = self.run(cmd, True)
            if ret != return_code:
                if hasattr(self, ignore_failed):
                    if getattr(self, ignore_failed):
                        self._print("INFO: ignore this failed from cmd %s " % cmd)
                    else:
                        if not self.debug_cmd(cmd):
                            self._print("FAIL: the ret %s, out is >%s<,  set return_code %s , cmd >%s<" % (ret, out, return_code, cmd))
                            status = False
                            raise RuntimeError('ignore_failed function dont get True')
                else:
                    if not self.debug_cmd(cmd):
                        self._print("FAIL: the ret %s, out is >%s<,  set return_code %s , cmd >%s<" % (ret, out, return_code, cmd))
                        status = False
                        raise RuntimeError('the cmd return code is not right and dont set ignore failed')
        else:
            self._print("FAIL: the key %s in the cmd >%s< can not find in %s help" % (miss_key, cmd, self.cmd))
        linux.sleep(5)
        cmd_ops["spec"] = spec
        cmd_ops["device"] = device
        cmd_ops["cmd"] = cmd
        cmd_ops["out"] = out
        cmd_ops["action"] = action
        cmd_ops["dmname"] = dmname
        cmd_ops["status"] = status
        return cmd_ops


