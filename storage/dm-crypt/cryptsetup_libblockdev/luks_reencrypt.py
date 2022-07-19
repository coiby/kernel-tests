#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import absolute_import, division, print_function, unicode_literals
__author__ = "Guazhang"
__copyright__ = "Copyright (c) 2016 Red Hat, Inc. All rights reserved."

import os
import gi
gi.require_version("GLib", "2.0")
gi.require_version("BlockDev", "2.0")
from gi.repository import GLib
from gi.repository import BlockDev as bd
import random
from luks import Luks

class reencrypt(Luks):
    def __init___(self,):
        supper().__init__(self,)

    def open_crypt(self, device, pwd=None, hdr=None,):
        if (pwd and hdr) :
            o_info = self.run_cmd(device, action="luksOpen", dmname=self.dmname, header=hdr, set_passwd=pwd,)
        elif pwd:
            o_info = self.run_cmd(device, action="luksOpen", dmname=self.dmname,set_passwd=pwd,)
        else:
            o_info = self.run_cmd(device, action="luksOpen", dmname=self.dmname,set_passwd=False, key_file=self.key1 )
        if not o_info['status']:
            self_print("FAIL: Could not open it")
            return False
        return True

    def wipe_dev_head(self, dev, length):
        self.run("dd if=/dev/zero of=$1 bs=1M count=$2 conv=notrunc" % (dev, length), False,False)

    def wipe_dev(self, dev, seek=None):
        cmd="dd if=/dev/zero of=%s bs=1M conv=notrunc" % dev
        if seek :
            cmd += ' seek=%s' % seek
        self.run(cmd,False,False)

    def wipe(self, dev, pwd=None, hdr=None):
        if not self.open_crypt(device=dev, pwd=pwd, hdr=hdr,):
            self._print("FAIL: open faied in wipe")
        self.wipe_dev("/dev/mapper/%s" % self.dmname)
        self.run("udevadm settle", False,False)
        self.remove_crypt(self.dmname)



    def reencrypt_test(self, device):
        self.cmd = 'cryptsetup'
        #new_one = self.range_str(10)
        dmname = self.range_str(10)
        self.dmname = dmname
        self.key1 = self.luks_keyfile(32)
        #luks_header = self.luks_header()
        #key1 = self.luks_keyfile(32)
        #key2 = self.luks_keyfile(16)
        #key5 = self.luks_keyfile(16)
        #self.run("touch /tmp/keye")
        #keye='/tmp/keye'
        #token0="keydesc0"
        #token1="keydesc1"
        #token2="keydesc2"
        #IMPORT_TOKEN='{"type":"some_type","keyslots":[],"base64_data":"zxI7vKB1Qwl4VPB4D-N-OgcC14hPCG0IDu8O7eCqaQ"}'


        f_info = self.run_cmd(device, action='luksFormat', type='luks2', key_size=128, cipher='aes-cbc-essiv:sha256', offset='8192',
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.wipe(device, self.passwd)

        f_info = self.run_cmd(device, action='reencrypt', pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: could not reencrypt with cmd %s" % f_info['cmd'])
            return False
        f_info = self.run_cmd(device, action='reencrypt',  key_size=256, cipher='twofish-cbc-essiv:sha256',
                resilience='journal',
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False

        f_info = self.run_cmd(device, action='reencrypt',  key_size=128, cipher='aes-cbc-essiv:sha256',
                resilience='checksum',
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False


        f_info = self.run_cmd(device, action='reencrypt', cipher='aes-xts-plain64', spec=('-q','--init-only'),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False

        f_info = self.run_cmd(device, action='reencrypt',  key_size=128, cipher='aes-cbc-essiv:sha256',
                resilience='checksum',
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False

        # cryptsetup don't support --force-offline-reencrypt
        #f_info = self.run_cmd(device, action='reencrypt', sector_size=4096,
        #        spec=('-q','--force-offline-reencrypt'),
        #         pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        #if not f_info['status']:
        #    self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
        #    return False


        f_info = self.run_cmd(device, action='reencrypt', sector_size=4096, resilience='none',
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False


        f_info = self.run_cmd(device, action='reencrypt', sector_size=512, key_size=128,
                cipher='aes-cbc-essiv:sha256', resilience='checksum',
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False


        self.run_cmd(device, action='open', dmname=dmname,)
        mapper_name = "/dev/mapper/%s" % dmname
        self.run_cmd(action='reencrypt', active_name=mapper_name, resilience='none')
        self.run_cmd(action='status', dmname=dmname, set_passwd=False,)
        self.remove_crypt(dmname)
        self.wipe_dev(device)



    def reencrypt_data_shift(self, device):
        self.cmd = 'cryptsetup'
        #new_one = self.range_str(10)
        dmname = self.range_str(10)
        self.key1 = self.luks_keyfile(32)
        luks_header = self.luks_header()

        f_info = self.run_cmd(device, action='reencrypt',key_size=128, reduce_device_size='8M',
                cipher='aes-cbc-essiv:sha256', spec=('-q','--encrypt'),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.wipe_dev(device)

        f_info = self.run_cmd(device, action='reencrypt',key_size=128, reduce_device_size='21M',
                cipher='twofish-cbc-essiv:sha256', spec=('-q','--encrypt'),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.wipe_dev(device)


        f_info = self.run_cmd(device, action='reencrypt',key_size=128, reduce_device_size='30M', offset=21504,
                cipher='twofish-cbc-essiv:sha256', spec=('-q','--encrypt'),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.wipe_dev(device)

        f_info = self.run_cmd(device, action='reencrypt', reduce_device_size='33M',
                spec=('-q','--encrypt'),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.wipe_dev(device)

        f_info = self.run_cmd(device, action='reencrypt', reduce_device_size='64M',
                spec=('-q','--encrypt'),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.wipe_dev(device)


        f_info = self.run_cmd(device, action='reencrypt',reduce_device_size='8M',
                spec=('-q','--encrypt','--init-only'),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.wipe_dev(device)


        f_info = self.run_cmd(device, action='reencrypt',key_size=128, reduce_device_size='8M', offset=32760,
                cipher='aes-cbc-essiv:sha256', spec=('-q','--encrypt','--init-only'),return_code=1,
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.wipe_dev(device)


        f_info = self.run_cmd(device, action='reencrypt',reduce_device_size='21M', offset=43008,
                spec=('-q','--encrypt'), header=luks_header,
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.wipe_dev(device)

        print(dmname)
        f_info = self.run_cmd(device, action='reencrypt',key_size=128, reduce_device_size='8M', key_slot=11,
                cipher='aes-cbc-essiv:sha256', spec=('-q','--encrypt','--init-only',dmname),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.run_cmd(device,action='reencrypt', spec=('-q','--resume-only'))


        f_info = self.run_cmd(device, action='reencrypt',key_size=128, reduce_device_size='8M', key_slot=11,
                cipher='aes-cbc-essiv:sha256', spec=('-q','--encrypt','--init-only',dmname), return_code=1,
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.remove_crypt(dmname)
        self.wipe_dev(device)

        self.run("echo -n '%s' > %s" % (self.passwd, self.key1),False,False)
        f_info = self.run_cmd(device, action='reencrypt',key_size=128, reduce_device_size='8M', key_file=self.key1,
                cipher='aes-cbc-essiv:sha256', spec=('-q','--encrypt','--init-only',dmname),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        if not f_info['status']:
            self._print("FAIL: Could not foramt with the cmd %s" % f_info['cmd'])
            return False
        self.remove_crypt(dmname)
        self.run_cmd(device, action='open',dmname=dmname, spec=('-q','--test-passphrase'))
        self.wipe_dev(device)




    def reencrypt_with_header(self, device):
        self.cmd = 'cryptsetup'
        #new_one = self.range_str(10)
        dmname = self.range_str(10)
        self.dmname = dmname
        self.key1 = self.luks_keyfile(32)
        luks_header = self.luks_header()

        self.run_cmd(device, action='reencrypt',key_size=128, header=luks_header,
                cipher='aes-cbc-essiv:sha256',spec=('-q','--encrypt'),
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        self.wipe_dev(device)
        os.remove(luks_header)


        luks_header = self.luks_header()
        self.run_cmd(device, action='reencrypt', header=luks_header, resilience='none',
                cipher='twofish-cbc-essiv:sha256', spec=('-q','--encrypt'), key_size=128,
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        self.wipe_dev(device)
        os.remove(luks_header)

        luks_header = self.luks_header()
        self.run_cmd(device, action='reencrypt', header=luks_header, resilience='checksum',
                cipher='serpent-xts-plain', spec=('-q','--encrypt'), key_size=128,
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        self.wipe_dev(device)
        os.remove(luks_header)


        luks_header = self.luks_header()
        self.run_cmd(device, action='reencrypt', header=luks_header,
                cipher='aes-cbc-essiv:sha256', spec=('-q','--encrypt',dmname), key_size=128,
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1)
        self.run_cmd(action='status', dmname=dmname, set_passwd=False,)
        # Device reencryption not in progress
        #self.run_cmd(action='reencrypt', header=luks_header, active_name=dmname, spec=('-q','--resume-only'))
        self.run_cmd(device, action='reencrypt', cipher='aes-cbc-essiv:sha256', spec=('-q','--encrypt',dmname), key_size=128,
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1, return_code=1)
        self.remove_crypt(dmname)
        os.remove(luks_header)
        self.wipe_dev(device)

        self.run("dd if=/dev/urandom of=%s bs=512 count=32768" % device,False,False)
        luks_header = self.luks_header()
        self.run_cmd(device, action='reencrypt', spec=('-q','--encrypt'), offset=32768, header=luks_header,
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)
        os.remove(luks_header)
        self.wipe_dev(device)


        luks_header = self.luks_header()
        self.run("echo -n '%s' > %s" % (self.passwd, self.key1),False,False)
        self.run_cmd(device, action='reencrypt', spec=('-q','--encrypt','--init-only',dmname), key_size=128,
                offset=32768, header=luks_header,cipher='aes-cbc-essiv:sha256', key_file= self.key1,
                 pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)
        self.run_cmd(action='status', dmname=dmname, set_passwd=False)
        self.remove_crypt(dmname)
        self.run_cmd(device, action='open', header=luks_header, spec=('--test-passphrase',))
        #os.remove(luks_header)

        # 4
        self.wipe(device, pwd=self.passwd, hdr=luks_header)
        self.run_cmd(device, action='reencrypt',key_size=128,
                header=luks_header,cipher='aes-cbc-essiv:sha256',
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)

        self.run_cmd(device, action='reencrypt', resilience='journal',
                header=luks_header,
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)

        self.run_cmd(device, action='reencrypt',key_size=128, resilience='none',
                header=luks_header,cipher='twofish-cbc-essiv:sha256',
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)


        self.run_cmd(device, action='reencrypt', resilience='checksum',
                header=luks_header,cipher='serpent-xts-plain',
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)

        self.run("dd if=/dev/zero of=%s bs=4k count=1" % luks_header, False, False)

        self.run_cmd(device, action='luksFormat',key_size=128, type='luks2',
                header=luks_header,cipher='aes-cbc-essiv:sha256',
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)

        self.run_cmd(device, action='open', dmname=dmname,header=luks_header,)
        self.run_cmd(device, action='reencrypt', active_name=dmname, header=luks_header,)

        self.remove_crypt(dmname)


        self.run_cmd(device, action='luksFormat',key_size=128, type='luks2', sector_size=512,
                header=luks_header,cipher='aes-cbc-essiv:sha256',
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)
        self.wipe(device, pwd=self.passwd, hdr=luks_header)
        self.run_cmd(device, action='reencrypt',header=luks_header, spec=('-q','--decrypt'))

        self.run_cmd(device, action='luksFormat', type='luks2',
                header=luks_header,
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)
        self.wipe(device, pwd=self.passwd, hdr=luks_header)
        self.run_cmd(device, action='reencrypt',header=luks_header, resilience='journal',spec=('-q','--decrypt'))

        self.run_cmd(device, action='luksFormat', type='luks2', key_size=128,
                header=luks_header, cipher='twofish-cbc-essiv:sha256',
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)
        self.wipe(device, pwd=self.passwd, hdr=luks_header)
        self.run_cmd(device, action='reencrypt',header=luks_header, resilience='none',spec=('-q','--decrypt'))

        self.run_cmd(device, action='luksFormat', type='luks2', cipher='serpent-xts-plain',
                header=luks_header,
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)
        self.wipe(device, pwd=self.passwd, hdr=luks_header)
        self.run_cmd(device, action='reencrypt',header=luks_header, resilience='checksum',spec=('-q','--decrypt'))


        self.run_cmd(device, action='luksFormat', type='luks2', cipher='serpent-xts-plain',
                header=luks_header, sector_size=4096,
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)

        self.open_crypt(device, pwd=self.passwd, hdr=luks_header,)
        self.run_cmd(action='status', dmname=dmname, set_passwd=False)

        self.run_cmd(device, action='reencrypt',header=luks_header, resilience='checksum',
                active_name=dmname, spec=('-q','--decrypt'))


        self.run_cmd(device, action='luksFormat', type='luks2', cipher='serpent-xts-plain',
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)

        self.run_cmd(device, action='reencrypt', spec=('-q','--decrypt'), return_code=1)


        # 6
        self.run_cmd(device, action='luksFormat', type='luks2', sector_size=512, offset=8192,
                pbkdf_force_iterations=4 , pbkdf_memory=32, pbkdf_parallel=1,)
        self.wipe(device, pwd=self.passwd,)




