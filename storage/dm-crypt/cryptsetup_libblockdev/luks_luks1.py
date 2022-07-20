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

class crypt_luks1(Luks):
    def __init___(self,):
        supper().__init__(self,)

    def compat_test(self, device):
        self.cmd='cryptsetup'
        new_one = self.range_str(10)
        luks_header = self.luks_header()

        format_info = self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000)
        if format_info['status'] :
            self.run_cmd(device, action='open', spec=('--test-passphrase',) ,set_passwd='wrong_passwd', return_code=2)
            self.run_cmd(device, action='open', spec=('--test-passphrase',))

        # header file
        format_info = self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000, header=luks_header)
        if format_info['status'] :
            self.run_cmd(device, action='open', spec=('--test-passphrase',), header=luks_header)

            # add/remove key/change key
            #cmd="echo -e '%s\nmymJeD8ivEhE'| cryptsetup luksAddKey %s --pbkdf pbkdf2 --pbkdf-force-iterations 1000" % (self.passwd, device)
            #self.run(cmd,)
            self.luks_add_key(device, old_key=self.passwd, new_key=new_one, pbkdf='pbkdf2',pbkdf_force_iterations=1000,)

            self.luks_dump(device, option="")
            cmd="echo -e '%s\ncompatkey\n' | cryptsetup luksChangeKey --pbkdf pbkdf2 --pbkdf-force-iterations 1000 %s" % (new_one,device)
            self.run(cmd,)
            self.luks_dump(device, option="")
            cmd="echo %s | cryptsetup luksRemoveKey %s" % (self.passwd, device)
            self.run(cmd,)
            self.luks_dump(device, option="")
            self.run_cmd(device, action='open', spec=('--test-passphrase',),return_code=2)
            self.run_cmd(device, action='open', spec=('--test-passphrase',),set_passwd='compatkey')

        # header backup
        info = self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000)
        if info['status'] :
            luks_header_new = self.luks_header()+'new'
            self.run_cmd(device, action='luksHeaderBackup', header_backup_file=luks_header_new)
            self.run_cmd(device, action='luksRemoveKey')
            self.run_cmd(device, action='open', spec=('--test-passphrase',), return_code=1)
            self.run_cmd(device, action='luksHeaderRestore', header_backup_file=luks_header_new)
            self.run_cmd(device, action='open', spec=('--test-passphrase',))

        # luksDump
        uuid='12345678-1234-1234-1234-123456789abc'
        info = self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000, uuid=uuid,)
        if info['status'] :
            #self.run("cryptsetup luksDump %s | grep -q 'Key Slot 0: ENABLED'" % device)
            #self.run("cryptsetup luksDump %s | grep -q %s" % (device, uuid))
            #self.run_cmd(device, action='luksDump',  spec=('--dump-volume-key',), return_code=1)
            #self.run_cmd(device, action='luksDump',  spec=('--dump-master-key',),)
            self.luks_dump(device, option="", grep='Key Slot 0: ENABLED')
            self.luks_dump(device, option="", grep=uuid)
            #self.run_cmd(device, option="--dump-volume-key", grep='MK dump:')
            self.run_cmd(device, action='luksDump', spec=("-q", " --dump-master-key ",))
            self.run_cmd(device, action='luksDump', spec=("-q", " --dump-master-key ",), grep='MK dump:')
            # case 1
            dmname = self.range_str(4)
            self.run_cmd(device, action="open", dmname=dmname, type='luks1')
            #org_sha256=self.run("sha256sum -b /dev/mapper/%s | cut -f 1 -d' '" % dmname)
            self.remove_crypt(dmname)

            # case 2
            self.run_cmd(device, action="open", dmname=dmname, type='luks1', set_passwd="wrong_passwd", return_code=2)

        # case 3
        info = self.run_cmd(device, action='luksFormat', iter_time=1000, cipher='aes_cbc_essiv:sha256',
                key_size=128, type='luks1' )
        if not info['status']:
            self._print("FAIL: case 3")

        # case 4
        info = self.run_cmd(device, action='luksFormat', iter_time=1000, cipher='aes_cbc_essiv:sha256',
                key_size=128, type='luks1',hash='sha512', )
        if not info['status']:
            self._print("FAIL: case 4")

            # case 5
            self.run_cmd(device, action="open", dmname=dmname, type='luks1', spec=('--test-passphrase',))
            open_info = self.run_cmd(device, action="open", dmname=dmname, type='luks1', )
            if not open_info['status'] :
                self._print("FAIL: case 5")
            self.remove_crypt(dmname)

            # case 6
            #self.run("echo -e '%s\nPASSWDPASSWD' | cryptsetup luksAddKey %s" % (self.passwd, device))
            if not self.luks_add_key(device, old_key=self.passwd, new_key=new_one):
                self._print("FAIL: add key in case 6")
            if not self.run_cmd(device, action="open", dmname=dmname, type='luks1', set_passwd=new_one)['status']:
                self._print("FAIL: open key in case 6")
            self.remove_crypt(dmname)

            # case 7
            if not self.run_cmd(device, action='luksKillSlot', dmname=1, return_code=2, set_passwd='wrong_passwd')['status']:
                self._print("FAIL: luksKillslot 1 in case 7")

            if not self.run_cmd(device, action='luksKillSlot', dmname=7, return_code=1)['status']:
                self._print("FAIL: luksKillslot 7 in case 7")

            if not self.run_cmd(device, action='luksKillSlot', dmname=8, return_code=1)['status']:
                self._print("FAIL: luksKillslot 8 in case 7")

            # case 8
            if not self.run_cmd(device, action='luksKillSlot', dmname=1)['status']:
                self._print("FAIL: luksKillslot 1 in case 8")

            self.run_cmd(device, action="open", dmname=dmname, type='luks1', set_passwd='PASSWDPASSWD', return_code=2)
            self.run_cmd(device, action="open", dmname=dmname, type='luks1')
            self.remove_crypt(dmname)

        # case 12
        key1 = self.luks_keyfile(128)
        if self.run_cmd(device, action='luksFormat', iter_time=1000, cipher='aes-cbc-essiv:sha256',
                key_size=128, type='luks1' ,key_file=key1, set_passwd=False,)['status']:
            self.run_cmd(device, action='open', dmname=dmname, key_file=key1)
            self.remove_crypt(dmname)

        # case 13
        if self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000)['status']:
            self.run_cmd(device, action='open', dmname=dmname)
            new_dev = '/dev/mapper/%s' % dmname
            self.run_cmd(new_dev, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000)
            self.run_cmd(new_dev, action='open', dmname='dummy')
            self.remove_crypt('dummy')
            self.remove_crypt(dmname)

        # 14
        new_one = self.range_str(10)
        cmd="echo -n -e '%s\n%s'|cryptsetup --pbkdf pbkdf2 --pbkdf-force-iterations 1000 -q \
                --key-file=- luksFormat --type luks1 %s" % (self.passwd, new_one, device)
        ret = self.run(cmd)
        if ret == 0 :
            cmd="echo -n -e '%s\n%s'|cryptsetup -q --key-file=- open %s %s" % (self.passwd, new_one, device, dmname)
            self.run(cmd)
            self.remove_crypt(dmname)

        # 16 no --volume-key-file, skip
        # 19
        if self.run_cmd(device=dmname, action='create', dmname=device, hash='sha256',
                cipher='aes_cbc_essiv:sha256', offset=8, skip=4, spec=('-q', '--readonly',))['status']:
            self.run_cmd(action='status', dmname=dmname)
            self.run_cmd(action='status', dmname=dmname, grep= '8 sectors')
            self.run_cmd(action='status', dmname=dmname, grep= '4 sectors')
            self.run_cmd(action='status', dmname=dmname, grep= 'readonly')
            self.run_cmd(action='resize', dmname=dmname, size=80)
            self.run_cmd(action='status', dmname=dmname, grep= '80 sectors')
            self.run_cmd(action='resize', dmname=dmname,)
            self.run_cmd(action='resize', dmname=dmname, device_size='8M')
            self.run_cmd(action='status', dmname=dmname, grep= '16384 sectors')
            self.run_cmd(action='resize', dmname=dmname,)
            self.run_cmd(action='remove', dmname=dmname,)

            # 27
        if self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, key_slot=5,)['status']:
            self.run_cmd(device, action='open', dmname=dmname, key_slot=4, return_code=1,)
            self.run_cmd(device, action='open', dmname=dmname, key_slot=5)
            self.remove_crypt(dmname)
            self.run('lsblk')
            #cmd="echo -e '%s\n%s'| cryptsetup luksAddKey %s --pbkdf pbkdf2 --pbkdf-force-iterations \
            #1000 -S 0 " % (self.passwd, new_one, device)
            #self.run(cmd)
            self.luks_add_key(device, old_key=self.passwd, new_key=new_one, key_slot=0,
                pbkdf='pbkdf2',pbkdf_force_iterations=1000,)
            self.run('lsblk')
            self.run_cmd(device, action='open', dmname=dmname,)
            self.run_cmd(device, action='open', dmname=dmname, set_passwd=new_one, return_code=5, )
            self.remove_crypt(dmname)

        key5 = self.luks_keyfile(128)
        if self.run_cmd(device, action='luksFormat', type='luks1', key_slot=5, key_file=key5)['status']:
            self.run_cmd(device, action='open', dmname=dmname, key_slot=5, key_file=key5)
            self.remove_crypt(dmname)

        # 28
        if self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                header=luks_header)['status']:
            self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                header=luks_header, align_payload=1, return_code=1,)
            self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                header=luks_header, align_payload=8192)
            self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                header=luks_header, align_payload=0)
            self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                header=luks_header, align_payload=8192, offset=8192, return_code=1)
            self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                header=luks_header, key_slot=7 )
            self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                header=luks_header, offset=80000 )
            self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                header=luks_header, offset=8192 )
            self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                header=luks_header, offset=0 )

            self.run_cmd(device, action='open', dmname=dmname, header=luks_header)
            self.run_cmd(dmname, action='resize', size=80, header=luks_header)
            self.run_cmd(dmname, action='status', header=luks_header,)
            self.run_cmd(dmname, action='status', header=luks_header, grep='80 sectors')
            self.run_cmd(dmname, action='status', grep='80 sectors')
            self.run_cmd(dmname, action='luksSuspend', header=luks_header)
            self.run_cmd(dmname, action='luksResume', header=luks_header)
            self.remove_crypt(dmname)


            self.run_cmd(device='_fake_dev_', action='luksAddKey', type='luks1', key_slot=5,
                pbkdf='pbkdf2', pbkdf_force_iterations=1000, header=luks_header, dmname=key5)
            self.run_cmd(device='_fake_dev_', action='luksDump',header=luks_header )
            self.run_cmd(device='_fake_dev_', action='luksDump',header=luks_header, grep='Key Slot 5: ENABLED' )
            self.run_cmd(device='_fake_dev_', action='luksKillSlot',header=luks_header, dmname=5 )
            self.run_cmd(device='_fake_dev_', action='luksDump',header=luks_header, grep='Key Slot 5: DISABLED' )
            #self.run_cmd(action='open', spec=("--test-passphrase", luks_header))

        # 29
        if self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                key_slot=0, dmname=key1)['status']:
            self.run("dd if=/dev/urandom of=%s bs=512 seek=1 count=1" % device)
            self.run_cmd(device, action='open', dmname=dmname, key_file=key1, return_code=1)
            self.run_cmd(device, action='repair')
            self.run_cmd(device, action='open', dmname=dmname, key_file=key1,)
            self.remove_crypt(dmname)

        if self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                hash='sha256', cipher='aes_ecb', dmname=key1)['status']:
            # this will failed, need to check
            #self.run('echo -n "ecb-xxx" | dd of=%s bs=1 seek=40 >/dev/null 2>&1' % device)
            #self.run_cmd(device, action='repair')
            #self.run_cmd(device, action='open', dmname=dmname, key_file=key1,)
            #self.remove_crypt(dmname)

            self.run('echo -n "SHA256" | dd of=%s bs=1 seek=72 >/dev/null 2>&1' % device)
            self.run_cmd(device, action='repair')
            self.run_cmd(device, action='open', dmname=dmname, key_file=key1,)
            self.remove_crypt(dmname)

        # 30
        if self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                key_slot=5, dmname=key5)['status']:
            self.run_cmd(device, action='luksAddKey', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                key_slot=1, dmname=key1, key_file=key5,)
            self.run_cmd(device, action='luksDump', grep='Key Slot 1: ENABLED')
            self.run_cmd(device, action='luksDump', grep='Key Slot 5: ENABLED')
            self.run_cmd(device, action='luksErase',)
            self.run_cmd(device, action='luksDump', grep='Key Slot 5: DISABLED')
            self.run_cmd(device, action='luksDump', grep='Key Slot 1: DISABLED')





