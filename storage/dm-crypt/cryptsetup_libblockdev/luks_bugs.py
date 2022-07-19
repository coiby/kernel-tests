#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import absolute_import, division, print_function, unicode_literals
__author__ = "Guazhang"
__copyright__ = "Copyright (c) 2016 Red Hat, Inc. All rights reserved."

import gi
gi.require_version("GLib", "2.0")
gi.require_version("BlockDev", "2.0")
from gi.repository import GLib
from gi.repository import BlockDev as bd

from luks import Luks

class crypt_bugs(Luks):
    def __init___(self,):
        supper().__init__(self,)


    def test_luks(self, device):
        self.cmd = 'cryptsetup'
        format_info = self.run_cmd(device, action="luksFormat", type='luks2')
        self.run("lsblk")
        dmname = self.range_str(4)
        self.luks_dump(device, option="")
        new_pass = self.range_str(10)
        key_des  = 'mykey'
        self.load_keying(new_pass, key_des)
        self.run_cmd(device, action="token add", set_passwd=False, key_description=key_des, token_id=10, )
        self.luks_dump(device, option="")

        self.run('cryptsetup token export %s --token-id %s > export_token' % (device, 10))
        self.run('cryptsetup token import %s --token-id %s --json-file %s' % (device, 20, 'export_token'))
        self.luks_dump(device, option="")

        open_info = self.run_cmd(device, action="open", dmname=dmname, spec=("-q", "--allow-discards",), type='luks2')
        bd.crypto_luks_resize(dmname, 10240, self.passwd)
        self.run("lsblk")
        self.luks_dump(device, option="")
        bd.crypto_luks_resize(dmname, 0, self.passwd)
        self.remove_crypt(dmname)
        self.run("lsblk")

    def luks_paramter(self, device):
        self.cmd = 'cryptsetup'
        types = ['luks2',]
        ciphers = [("aes-cbc-essiv:sha256",256),("aes-cbc-essiv:sha3-256",256),
                #("capi:cbc(aes)-essiv:sha3-256",256),
               ("twofish-ecb",256),("serpent-cbc-plain",256),("twofish-xts-plain64",512)]
        hashs = ["sha256", "sha512"]
        iter_times = [20, 30000]
        dmname = self.range_str(4)
        sector_size=4096
        for c in ciphers:
            for iter_time in iter_times:
                for h in hashs:
                    format_info = self.run_cmd(device, action="luksFormat", cipher=c[0], type='luks2',
                            key_size=c[1], hash=h, iter_time=iter_time, sector_size=sector_size,)

                    open_info = self.run_cmd(device, action="open", dmname=dmname, type='luks2',
                            spec=("-q", "--allow-discards",))

                    self.luks_dump(device, option="")
                    self.luks_dump(device, option="", grep=c[0])
                    bd.crypto_luks_resize(dmname, 10240, self.passwd)
                    self.run("lsblk")
                    self.remove_crypt(dmname)
                    self.run("lsblk")



    def luks_bz1750680(self, device):
        self.cmd = 'cryptsetup'
        format_info = self.run_cmd(device, action="luksFormat", type='luks2')
        self.run("lsblk")
        self.luks_dump(device, option="")
        dmname = self.range_str(4)
        open_info = self.run_cmd(device, action="open", dmname=dmname,
                                spec=("-q", "--disable-keyring",), type='luks2')
        if open_info['status']:
            if not self.luks_status(dmname, grep='dm-crypt'):
                self._print("FAIL: luks_bz1750680 status check ")
                return False
        else:
            self._print("FAIL: open luks with --disable-keyring")
            return False
        self.remove_crypt(dmname)
        self.run("lsblk")
        return True

    def luks_bz2073433(self, device):
        self.cmd = 'cryptsetup'
        spec=["-q", "--perf-no_read_workqueue", "--perf-no_write_workqueue"]
        dmname = self.range_str(4)

        for t in ['luks1', 'luks2']:
            format_info = self.run_cmd(device, action="luksFormat", type=t)
            self.run("lsblk")
            self.luks_dump(device, option="")
            if t == 'luks2':
                spec.append('--persistent')
            open_info = self.run_cmd(device, action="open", dmname=dmname,
                                spec=tuple(spec), type=t)
            self.luks_dump(device, option="")
            self.luks_status(dmname, grep='workqueue')
            self.run_cmd(action="refresh", dmname=dmname, spec=('-q','--perf-no_write_workqueue'))
            self.luks_status(dmname, grep='no_write_workqueue')
            self.run_cmd(action="refresh", dmname=dmname, spec=('-q','--perf-no_read_workqueue'))
            self.luks_status(dmname, grep='no_read_workqueue')
            self.run_cmd(action="refresh", dmname=dmname, spec=('-q','--perf-no_write_workqueue','--perf-no_read_workqueue'))
            self.luks_status(dmname, grep='workqueue')
            self.remove_crypt(dmname)
            self.run("lsblk")

        return True

    def luks_conversion(self, device):
        self.cmd = 'cryptsetup'
        dmname = self.range_str(4)
        self.run_cmd(device, action="luksFormat", type='luks1')
        self.run("lsblk")
        self.luks_dump(device, option="")
        c_type = ['luks2','luks1','luks2']
        for t in c_type:
            self.run_cmd(device, action="convert", type=t)
            self.run_cmd(device, action="open", dmname=dmname, type=t)
            self.luks_dump(device, option="")
            self.luks_status(dmname)
            self.remove_crypt(dmname)
            self.run("lsblk")
        self.luks_dump(device, option="")
        self.run("lsblk")





    # run_cmd(self, device="",action="",dmname="",set_passwd=True, spec=("-q",), **cmd_ops)
    def luks_bz1862173(self, device):
        self.cmd = 'cryptsetup'
        format_info = self.run_cmd(device, action="luksFormat", type='luks2')
        self.run("lsblk")
        self.luks_dump(device, option="")
        new_pass = self.range_str(10)
        key_des  = 'mykey'
        self.load_keying(new_pass, key_des)
        self.run_cmd(device, action="token add", set_passwd=False, key_description=key_des,)
        self.luks_dump(device, option="")
        dmname = self.range_str(4)
        # open without passwd
        ret, out=self.run_command('cryptsetup open %s %s' % (device, dmname))
        print(ret,out)
        if ret :
            self._print("FAIL: Could not open device %s without passwd" % device)
            print(out)
            return False
        #return True
        bd.crypto_keyring_add_key('mykey1', 'PASSWD1')
        new_pass = self.range_str(10)
        key_des  = 'mykey1'
        self.load_keying(new_pass, key_des)
        self.run_cmd(device, action="token add", set_passwd=False, key_description=key_des,)
        bd.crypto_luks_open_keyring(device, dmname, key_des,False )
        self.luks_dump(device, option="")
        self.remove_crypt(dmname)
        self.run("lsblk")



    def luks_passphrases(self, device):
        self.cmd = "cryptsetup"
        for t in ['luks1', 'luks2']:
            format_info = self.run_cmd(device, action="luksFormat", type=t)
            dmname = self.range_str(4)
            open_info = self.run_cmd(device, action="open", dmname=dmname, spec=("-q", "--allow-discards",), type=t,)
            self.run("lsblk")
            self.luks_dump(device, option="")
            npass = self.luks_keyfile(256)
            range_list=range(1,32)
            if t == 'luks1':
                range_list=range(1,8)
            for slot in range_list:
                self._print("INFO: add %s slot %s" % (t, slot))
                bd.crypto_luks_add_key(device, pass_=self.passwd, nkey_file=npass)
                self.luks_dump(device,  option="")
            for slot in range_list:
                self._print("INFO: remove %s slot %s" % (t, slot))
                bd.crypto_luks_remove_key(device, key_file=npass)
                self.luks_dump(device,  option="")
            dev_name = "/dev/mapper/%s" % dmname
            self.run_io(dev_name)
            self.luks_dump(device, option="")
            self.remove_crypt(dmname)
            self.run("lsblk")




    # run_cmd(self, device="",action="",dmname="",set_passwd=True, spec=("-q",), **cmd_ops)
    def integrity_setup(self, device,):
        self.cmd = "integritysetup"
        self.load_module("dm-integrity")
        self.run("dmsetup targets|grep -e integrity")
        format_info = self.run_cmd(device=device, action="format", spec=("-q",), progress_frequency=5,integrity="sha1",
                tag_size=20, sector_size=4096,)
        if not format_info["status"]:
            self._print("FAIL: Could not format the device %s with cmd %s" % (device, format_info["cmd"]))
            return
        dmname = self.range_str(4)
        open_info = self.run_cmd(device=device, action="open", dmname=dmname,spec=("-q","--integrity-no-journal",),integrity="sha1",)
        if not open_info["status"] :
            self._print("FAIL: Could not open the device %s with cmd %s" % (device,open_info["cmd"]))
        self.run("lsblk")
        io_device = "/dev/mapper/%s" % dmname
        self.run_io(io_device)
        self.run("lsblk")
        self.remove_crypt(dmname)



    # run_cmd(self, device="",action="",dmname="",set_passwd=True, spec=("-q",), **cmd_ops)
    def reencrypt_online(self, device):
        self.cmd = "cryptsetup"
        resilience_l=['none','checksum','journal']
        for res in resilience_l:
            format_info = self.run_cmd(device,action="luksFormat", type="luks2")
            dmname = self.range_str(4)
            open_info = self.run_cmd(device, action="open", dmname=dmname, spec=("-q", "--allow-discards",), type="luks2",)
            self.run("lsblk")
            dev_name = "/dev/mapper/%s" % dmname
            self.run_io(dev_name)
            self.luks_dump(device, option="")
            self.remove_crypt(dmname)
            self.run("lsblk")
            header_file = self.luks_header()
            info = self.run_cmd(device, action='reencrypt', spec=('-q', '--encrypt', '--init-only',), header=header_file,)
            self.run_cmd(device, action='open', dmname=dmname, spec=("--allow-discards",), type="luks2", header=header_file,)
            self.run("lsblk")
            self.luks_dump(device, option="", header=header_file)
            self.remove_crypt(dmname)

            self.run_cmd(device, action='reencrypt', header=header_file,)
            self.luks_dump(device, option="", header=header_file )
            self.run_cmd(device, action='open', dmname=dmname, spec=("-q","--allow-discards",), type="luks2", header=header_file)
            self.run("lsblk")
            self.luks_dump(device, option="", header=header_file)
            self.run_io(dev_name)
            self.luks_dump(device, option="", header=header_file)
            self.run_cmd(device, action='reencrypt', active_name=dmname, resilience=res, hotzone_size='100M',cipher='serpent-cbc-essiv:sha256',  header=header_file,)
            self.run_io(dev_name)
            self.run("lsblk")
            self.luks_dump(device, option="",  header=header_file )
            self.run_cmd(device, action='reencrypt',spec=('--decrypt',), active_name=dmname,  header=header_file )
        header_file = self.luks_header()
        dmname = self.range_str(4)
        dev_name = "/dev/mapper/%s" % dmname
        if hasattr(self, "devcie_type") :
            if getattr(self, "device_type") == "lvm":
                self.run_cmd(device, action='reencrypt', spec=('-q', '--encrypt','--init-only',), header=header_file,)
                self.run_cmd(device, action='reencrypt', header=header_file,)
                self.run_cmd(device, action='open', dmname=dmname, spec=("--allow-discards",), type="luks2", header=header_file,)
                self.run_cmd(device, action='reencrypt', active_name=dmname, hotzone_size='100M',cipher='serpent-cbc-essiv:sha256',  header=header_file,)
                self.run("lsblk")
                self.run_io(dev_name)

                cmd = "lvextend -L +1024M %s" % device
                ret, out = self.run(cmd,True)
                if ret :
                    self._print("FAIL: COuld not resize the lvm device %s" % device)
                    return
                self._print("INFO: have resize the device  %s OK" % device)
                if self.fs == "xfs" :
                    cmd="xfs_growfs "
                else:
                    cmd="resize2fs "
                self.run_io(dev_name)
                self.run("lsblk")
                self.add_fs(dev_name)
                self.add_mount(dev_name)
                self.run("%s %s" % (cmd, dev_name))
                self.remove_mount(dev_name)
                self.run_cmd(action="resize", dmname=dmname, device_size="1G", header=header_file)
                self.run("lsblk")
                self.run_cmd(action="resize", dmname=dmname, device_size="16G", header=header_file)
                self.run("lsblk")
                self.run_cmd(device, action='reencrypt',spec=('--decrypt',), active_name=dmname,  header=header_file )
                self.run("lsblk")


