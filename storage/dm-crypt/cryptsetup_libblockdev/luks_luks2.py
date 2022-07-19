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

from luks import Luks

class crypt_luks2(Luks):
    def __init___(self,):
        supper().__init__(self,)

    def compat_test2(self, device):
        self.cmd = 'cryptsetup'
        new_one = self.range_str(10)
        dmname = self.range_str(10)
        #luks_header = "/tmp/luks_header%s" % self.range_str(3)
        #self.run("truncate -s 4096 %s" % luks_header)
        luks_header = self.luks_header()
        key1 = self.luks_keyfile(32)
        key2 = self.luks_keyfile(16)
        key5 = self.luks_keyfile(16)
        self.run("touch /tmp/keye")
        keye='/tmp/keye'
        token0="keydesc0"
        token1="keydesc1"
        token2="keydesc2"
        IMPORT_TOKEN='{"type":"some_type","keyslots":[],"base64_data":"zxI7vKB1Qwl4VPB4D-N-OgcC14hPCG0IDu8O7eCqaQ"}'


        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', pbkdf_force_iterations=1000)
        self.luks_dump(device, option="")
        self.run_cmd(device, action='open', dmname=dmname,)
        self.run_cmd(action='status', dmname=dmname, set_passwd=False)
        if self.run_cmd(action='status', dmname=dmname, grep='keyring', set_passwd=False,)['status']:
            HAVE_KEYRING=1
        else:
            HAVE_KEYRING=0
        self.remove_crypt(dmname)

        # Data offset
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, offset=1, return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, offset=16385, return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, offset=32, return_code=1, )
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, offset=16384, align_payload=16384, return_code=1,)

        if self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, offset=16384)['status']:
            self.run_cmd(device, action='luksDump', grep='offset: %s' % (512*16384))
            self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, offset=16384, sector_size=1024,)

            self.run_cmd(device, action='luksDump', grep='offset: %s' % (512*16384))
            self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, offset=80000, header=luks_header)


        # Sector size and old payload alignment
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  sector_size=511, return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  sector_size=256, return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  sector_size=8192, return_code=1)

        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  sector_size=512)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  align_payload=5)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  align_payload=5, sector_size=512)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  align_payload=32, sector_size=2048)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,sector_size=4096)

        if self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  align_payload=32768, sector_size=2048)['status']:
            self.run_cmd(device, action='luksDump', grep='offset: %s' % (512*32768))

        if self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, sector_size=2048)['status']:
            self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  align_payload=32768, sector_size=4096)
            self.run_cmd(device, action='luksDump', grep='offset: %s' % (512*32768))

        # format
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, key_size=128, cipher='aes-cbc-essiv:sha256')

        # format using hash sha512
        if self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, key_size=128, hash='sha512',
                cipher='aes-cbc-essiv:sha256')['status']:
            self.run_cmd(device, action='luksDump', grep='sha512')

            if self.check_options(self.cmd, '--dump-json-metadata') :
                self.run_cmd(device, action='luksDump',  spec=('--dump-json-metadata',), grep='\"tokens\":' )
            # open
            self.run_cmd(device, action='open', spec=('--test-passphrase',) ,set_passwd='wrong_passwd', return_code=2)
            self.run_cmd(device, action='open', spec=('--test-passphrase',))
            self.run_cmd(device, action='open',dmname=dmname)
            self.remove_crypt(dmname)

            # add key
            #cmd="echo -e '%s\n%s'| cryptsetup luksAddKey %s --pbkdf pbkdf2 --pbkdf-force-iterations 1000" % (self.passwd, new_one, device)
            #self.run(cmd)

            self.luks_add_key(device, old_key=self.passwd, new_key=new_one,
                pbkdf='pbkdf2',pbkdf_force_iterations=1000,)


            self.run_cmd(device, action='open', spec=('--test-passphrase',) ,set_passwd=new_one,)

            # unsuccessful del
            self.run_cmd(device, action='luksKillSlot', dmname=1, set_passwd=new_one, return_code=2)

            # suceessful del
            self.run_cmd(device, action='luksKillSlot', dmname=1,)
            self.run_cmd(device, action='open', dmname=dmname, set_passwd=new_one, return_code=2)
            self.run_cmd(device, action='open', dmname=dmname,)
            self.remove_crypt(dmname)

            # 9
            self.run_cmd(device, action='luksAddKey', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, dmname=key1)
            self.run_cmd(device, action='open', dmname=dmname, key_file=key1,)
            self.remove_crypt(dmname)

            # 10
            self.run_cmd(device, action='luksKillSlot', dmname=0, key_file=key1)
            self.run_cmd(device, action='open', dmname=dmname, return_code=2)
            self.run_cmd(device, action='open', dmname=dmname, key_file=key1)
            self.remove_crypt(dmname)

            # delete last key
            self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,)
            self.run_cmd(device, action='luksKillSlot', dmname=0,)
            self.run_cmd(device, action='open', dmname=dmname, return_code=1)

        # essiv
        if self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', dmname=key1,
                pbkdf_force_iterations=1000, cipher='aes-cbc-essiv:sha256', key_size=128,
                set_passwd=False,)['status']:
            self.run_cmd(device, action='open', dmname=dmname, key_file=key1)
            self.remove_crypt(dmname)

        # stacked devices
        if self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,)['status']:
            self.run_cmd(device, action='open', dmname=dmname)
            new_dev = "/dev/mapper/%s" % dmname
            self.run_cmd(new_dev, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,)
            self.run_cmd(new_dev, action='open', dmname="dummy")
            self.remove_crypt("dummy")
            self.remove_crypt(dmname)

        #  passphrase on stdin & new line
        cmd="echo -n -e '%s\n%s' | cryptsetup --pbkdf pbkdf2 --pbkdf-force-iterations 1000 -q --key-file=- luksFormat \
        --type luks2 %s" % (self.passwd, new_one, device)
        self.run(cmd)
        cmd="echo -n -e '%s\n%s' | cryptsetup  -q --key-file=- luksOpen  %s %s" % (self.passwd, new_one, device, dmname)
        self.run(cmd)
        self.remove_crypt(dmname)

        # empty key
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, key_file=keye)
        self.run_cmd(device, action='open', dmname=dmname, key_file=keye)
        self.remove_crypt(dmname)

        # -
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  key_slot=3, dmname=key1)
        #cmd="echo %s| cryptsetup luksAddKey --pbkdf pbkdf2 --pbkdf-force-iterations \
        #        1000 %s -d %s -"%(self.passwd, device, key1,)
        #self.run(cmd)
        self.luks_add_key(device, old_key=self.passwd,  key_file=key1, spec=("-",),
                pbkdf='pbkdf2',pbkdf_force_iterations=1000,)

        self.run_cmd(device, action='open', spec=('--test-passphrase',), return_code=2 )
        self.run_cmd(device, action='open', spec=('--test-passphrase',),key_file='-', )
        self.run_cmd(device, action='luksAddKey', pbkdf='pbkdf2', key_file='-', dmname=key2,
                pbkdf_force_iterations=1000, )
        self.run_cmd(device, action='open', key_file=key2, spec=('--test-passphrase',), set_passwd=False,)

        # skip
        #self.run_cmd(device, action='open', key_file=key1, spec=('--test-passphrase', '-d -'),
        #        return_code=1,)
        #self.run_cmd(device, action='open', key_file=key1, spec=('--test-passphrase', '-d %s' % key1),
        #        return_code=1,)
        #
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  key_slot=3, dmname=key1)
        self.run_cmd(device, action='luksDump', grep='3: luks2', set_passwd=False)

        self.run_cmd(device, action='luksAddKey', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  key_slot=3, key_file=key1, dmname=key2, return_code=1,)
        # keyfile  keyfile
        self.run_cmd(device, action='luksAddKey', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  key_slot=4, key_file=key1, dmname=key2)

        self.run_cmd(device, action='open', key_file=key2, spec=('--test-passphrase', ), key_slot=4,)
        self.run_cmd(device, action='luksDump', grep='4: luks2', set_passwd=False,)
        self.run_cmd(device, action='luksAddKey', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  key_slot=0, key_file=key1,)
        self.run_cmd(device, action='luksDump', grep='0: luks2', set_passwd=False,)
        self.run_cmd(device, action='open', spec=('--test-passphrase', ), key_slot=0)
        #cmd="echo -e '93R4P4pIqAH8\nmymJeD8ivEhE\n' | cryptsetup luksAddKey --pbkdf pbkdf2 --pbkdf-force-iterations 1000 /dev/loop0 --key-slot 1"

        self.luks_add_key(device, old_key=self.passwd, new_key=new_one, key_slot=1,
                pbkdf='pbkdf2',pbkdf_force_iterations=1000,)
        self.run_cmd(device, action='open', spec=('--test-passphrase', ), key_slot=1, set_passwd=new_one,)
        self.run_cmd(device, action='luksDump', grep='1: luks2', set_passwd=False,)

        # keyfile/passphrase
        self.luks_add_key(device, old_key=new_one, key_slot=2,
                pbkdf='pbkdf2',pbkdf_force_iterations=1000, new_keyfile_size=3, spec=("-q", key1))
        self.run_cmd(device, action='luksDump', grep='2: luks2', set_passwd=False,)

        #  RemoveKey passphrase and keyfile
        self.run_cmd(device, action='luksDump',set_passwd=False,)
        self.run_cmd(device, action='luksDump', grep='3: luks2', set_passwd=False,)
        self.run_cmd(device, action='luksRemoveKey', set_passwd=False, spec=('-q', key1,))
        self.run_cmd(device, action='luksDump',set_passwd=False,)
        self.run_cmd(device, action='luksDump', grep='3: luks2', set_passwd=False, return_code=1, )
        self.run_cmd(device, action='luksDump',set_passwd=False,)
        self.run_cmd(device, action='luksRemoveKey', set_passwd=False, spec=('-q', key1,), return_code=2)
        self.run_cmd(device, action='luksRemoveKey', keyfile_size=1,  set_passwd=False, spec=('-q', key2,), return_code=2,)
        self.run_cmd(device, action='luksDump',set_passwd=False,)
        self.run_cmd(device, action='luksDump', grep='4: luks2', set_passwd=False,)
        self.run_cmd(device, action='luksRemoveKey', set_passwd=False, spec=(key2, '-q'))
        self.run_cmd(device, action='luksDump', grep='4: luks2', set_passwd=False, return_code=1)
        self.run_cmd(device, action='luksKillSlot', set_passwd='badpw', spec=('-q', 2,), return_code=2,)
        self.run_cmd(device, action='luksKillSlot', set_passwd='badpw', spec=('-q', 2,), return_code=2,)
        self.run_cmd(device, action='luksKillSlot', set_passwd='badpw', key_file='-', spec=(2, '-q'), return_code=2,)
        self.run_cmd(device, action='luksKillSlot', set_passwd='badpw', key_file='-', spec=(2, '-q'), return_code=2,)
        self.run_cmd(device, action='luksDump', grep='2: luks2', set_passwd=False)
        self.run_cmd(device, action='luksKillSlot', set_passwd=new_one, spec=(2,'-q'))
        self.run_cmd(device, action='luksDump', grep='2: luks2', set_passwd=False, return_code=1)
        self.run_cmd(device, action='luksRemoveKey',)
        self.run_cmd(device, action='luksDump', grep='0: luks2', set_passwd=False, return_code=1)
        self.run_cmd(device, action='luksKillSlot', spec=(1, '-q'), set_passwd=False,)
        self.run_cmd(device, action='luksDump', grep='1: luks2', set_passwd=False, return_code=1)


        # 19  create & status & resize

        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  key_slot=3)
        self.run_cmd(device, action='open', dmname=dmname,)
        if self.dm_crypt_keyring_support():
            self.run_cmd(action='resize', dmname=dmname, size=160, set_passwd=' ', return_code=2)
            if (HAVE_KEYRING > 0) and os.path.exists("/proc/sys/kernel/keys"):
                if self.test_and_prepare_keyring() :
                    # pwd1 = self.passwd
                    if not self.load_key("user %s %s %s" % (token2, self.passwd, self.test_keyring )):
                        self._print("FAIL: Could not add passwd %s to keyring" % self.passwd)
                    self.run_cmd(device, action='token add', key_description=token2, token_id=1, set_passwd=False)
                    self.run_cmd(action='resize',size=80, dmname=dmname, set_passwd=False)
                    self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='80 sectors')

                    # replace kernel key with wrong pass
                    if not self.load_key("user %s %s %s" % (token2, "wrong_passwd", self.test_keyring )):
                        self._print("FAIL: Could not add passwd %s to keyring" % "wrong_passwd")
                    # should failed
                    self.run_cmd(action='resize',size=160, dmname=dmname, spec=('-q','--token-only'), return_code=2)
                    self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='100 sectors', return_code=1)
        self.run_cmd(action='resize',size=160, dmname=dmname)
        self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='160 sectors')
        self.run_cmd(action='resize', device_size=81920, dmname=dmname)
        self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='160 sectors')
        self.run_cmd(action='resize', device_size='8M', dmname=dmname)
        self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='16384 sectors')
        self.run_cmd(action='resize', device_size='512k',size=1024,  dmname=dmname, return_code=1)
        self.run_cmd(action='resize', device_size=4097,dmname=dmname, return_code=1)
        self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='16384 sectors')
        self.remove_crypt(dmname)
        self.run_cmd(device, action='open', dmname=dmname, spec=('-q','--disable-keyring'))
        self.run_cmd(action='resize', size=160, dmname=dmname, set_passwd=' ', )
        self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='160 sectors')
        self.remove_crypt(dmname)

        self.run_cmd(device, action='open', dmname=dmname)
        if self.dm_crypt_keyring_support():
            self.run_cmd(action='resize', size=160, dmname=dmname,
                    set_passwd=False, spec=('-q','--disable-keyring'),return_code=1, )
        if self.dm_crypt_sector_size_support():
            self.remove_crypt(dmname)
            self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, sector_size=4096,)
            self.run_cmd(device, action='open', dmname=dmname)
            self.run_cmd(action='resize', device_size='8M', dmname=dmname,)
            self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='16384 sectors')
            self.run_cmd(action='resize', device_size='2049s' , dmname=dmname, return_code=1,)
            self.run_cmd(action='resize', size='2049' , dmname=dmname, return_code=1,)
            self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='16384 sectors')
        self.run_cmd(device, action='open', dmname="dummy2", return_code=5)
        self.remove_crypt(dmname)
        disk_info = bd.part_get_disk_spec(device)
        if disk_info.sector_size == 4096:
            self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000)
            self.run_cmd(device, action='open', dmname=dmname)
            self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='size')
            self.run_cmd(action='resize', dmname=dmname, size=8, )
            self.run_cmd(action='status', dmname=dmname, set_passwd=False, grep='size')
            self.remove_crypt(dmname)

        # 22
        cmd="dmsetup create %s --table '0 40960 linear %s 2'" % (dmname, device)
        if self.run(cmd) == 0:
            self.run_cmd("/dev/mapper/%s" % dmname, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000)
            self.run_cmd("/dev/mapper/%s" % dmname, action='open', dmname="dummy2")
            self.run("dmsetup load %s --table '0 40962 error'" % dmname)
            self.run("dmsetup resume %s" % dmname)
            self.remove_crypt("dummy2")
            self.run("dmsetup remove --retry %s" % dmname)

        # 24
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', set_passwd=False,
                pbkdf_force_iterations=1000, key_slot=0, keyfile_size=13, spec=('-q', key1))
        self.run_cmd(device, action='open', dmname=dmname, key_file=key1, set_passwd=False, return_code=2)
        self.run_cmd(device, action='open', dmname=dmname, key_file=key1, keyfile_size='0', set_passwd=False, return_code=2)
        self.run_cmd(device, action='open', dmname=dmname, key_file=key1, keyfile_size=-1, set_passwd=False, return_code=1)
        self.run_cmd(device, action='open', dmname=dmname, key_file=key1, keyfile_size=14, set_passwd=False, return_code=2)
        self.run_cmd(device, action='open', dmname=dmname, key_file=key1, keyfile_size=13,
                set_passwd=False,keyfile_offset=1, return_code=2)
        self.run_cmd(device, action='open', dmname=dmname, key_file=key1, keyfile_size=13,
                set_passwd=False,keyfile_offset=-1, return_code=1)
        self.run_cmd(device, action='open', dmname=dmname, key_file=key1, keyfile_size=13,
                set_passwd=False,)
        self.remove_crypt(dmname)
        self.run_cmd(device, action='luksAddKey', key_file=key1, spec=('-q', key2),
                set_passwd=False, return_code=2)
        self.run_cmd(device, action='luksAddKey', key_file=key1, spec=('-q', key2),keyfile_size=14,
                set_passwd=False, return_code=2)
        self.run_cmd(device, action='luksAddKey', key_file=key1, spec=('-q', key2),keyfile_size=-1,
                set_passwd=False, return_code=1)

        # RHEL8 failed
        #self.run_cmd(device, action='luksAddKey', key_file=key1, spec=('-q', key2),keyfile_size=13,
        #        set_passwd=False, new_keyfile_size=12, pbkdf='pbkdf2', pbkdf_force_iterations=1000,)

        self.run_cmd(device, action='luksRemoveKey', spec=('-q', key2), return_code=2, set_passwd=False)
        # RHEL8 failed
        # self.run_cmd(device, action='luksRemoveKey', spec=('-q', key2), keyfile_size=12, set_passwd=False)
        self.run_cmd(device, action='luksChangeKey', spec=('-q', key2), key_file=key1,
                return_code=2, set_passwd=False,)
        self.run_cmd(device, action='luksChangeKey', spec=('-q', key2), key_file=key1,
                keyfile_size=14, return_code=2, set_passwd=False)
        self.run_cmd(device, action='luksChangeKey', spec=('-q', key2), key_file=key1,
                keyfile_size=13,  pbkdf='pbkdf2', set_passwd=False, pbkdf_force_iterations=1000,  )
        self.run_cmd(device, action='luksChangeKey', key_file=key2,
                pbkdf='pbkdf2',pbkdf_force_iterations=1000,)

        self.run_cmd(device, action='luksRemoveKey', keyfile_size=11, return_code=2)
        self.run_cmd(device, action='luksRemoveKey', keyfile_size=12, return_code=2, set_passwd='wrong_passwd')
        #self.run_cmd(device, action='luksRemoveKey', keyfile_size=12, key_file='-')
        #cmd="echo -e '%s\n'|cryptsetup luksRemoveKey %s -d - -l 12 -q" % (self.passwd, device)
        #if self.run(cmd):
        #    self._print("FAIL: run cmd %s" % cmd)
        #    exit(0)
        # offset
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', set_passwd=False,
                pbkdf_force_iterations=1000, key_slot=0, keyfile_size=13, keyfile_offset=16, spec=('-q', key1))
        self.run_cmd(device, action='open', dmname=dmname, key_file=key1,
                keyfile_size=13, keyfile_offset=15, set_passwd=False, return_code=2)
        self.run_cmd(device, action='open', dmname=dmname, key_file=key1,
                keyfile_size=13, keyfile_offset=16, set_passwd=False,)
        self.remove_crypt(dmname)

        self.run_cmd(device, action='luksAddKey',pbkdf='pbkdf2', set_passwd=False, key_file=key1,
                pbkdf_force_iterations=1000,keyfile_size=13, keyfile_offset=16, spec=('-q', key2), new_keyfile_offset=1)

        self.run_cmd(device, action='open', dmname=dmname, key_file=key2,
                 keyfile_offset=11, set_passwd=False, return_code=2)

        self.run_cmd(device, action='open', dmname=dmname, key_file=key2,
                 keyfile_offset=1, set_passwd=False,)
        self.remove_crypt(dmname)

        self.run_cmd(device, action='luksChangeKey',pbkdf='pbkdf2', set_passwd=False, key_file=key2,
                pbkdf_force_iterations=1000,keyfile_offset=1, spec=('-q', key2), new_keyfile_offset=0)
        self.run_cmd(device, action='open', dmname=dmname, key_file=key2, set_passwd=False,)
        self.remove_crypt(dmname)

        # 28
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, header=luks_header)

        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',align_payload=1,
                pbkdf_force_iterations=1000, header=luks_header,  return_code=1,)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',align_payload=8192,
                pbkdf_force_iterations=1000, header=luks_header,)
        self.run_cmd(device, action='luksDump', dmname=luks_header, set_passwd=False,)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',align_payload=0,
                pbkdf_force_iterations=1000, header=luks_header, sector_size=512 )

        self.run_cmd('wrong_device', action='open', dmname=dmname, header=luks_header, return_code=4,)
        self.run_cmd(device, action='open', dmname=dmname, header=luks_header,)
        self.run_cmd(action='resize', dmname=dmname, size=160, header=luks_header)
        #self.run_cmd(action='luksDump', dmname=dmname, header=luks_header, grep='100 sectors', set_passwd=False,)
        self.run_cmd(action='status', dmname=dmname, header=luks_header, grep='160 sectors', set_passwd=False,)
        self.run_cmd(action='luksSuspend', dmname=dmname, header=luks_header, set_passwd=False,)
        self.run_cmd(action='luksResume', dmname=dmname, header=luks_header, )
        self.run_cmd(action='luksSuspend', dmname=dmname, header=luks_header, set_passwd=False,)
        self.run_cmd(action='luksResume', dmname=dmname, return_code=1)
        self.run_cmd(action='luksResume', dmname=dmname, header=luks_header,)
        self.remove_crypt(dmname)

        self.run_cmd('_fakedev', action='luksAddKey', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                key_slot=5, header=luks_header, spec=('-q', key5))

        self.run_cmd('_fakedev', action='luksDump', header=luks_header, grep= '5: luks2', set_passwd=False,)
        self.run_cmd('_fakedev', action='luksKillSlot', header=luks_header, spec=('-q', '5'), set_passwd=False,)
        self.run_cmd('_fakedev', action='luksDump', header=luks_header, grep= '5: luks2',
                set_passwd=False, return_code=1)

        self.run_cmd(action='open', spec=('--test-passphrase', luks_header))
        os.remove(luks_header)
        self.run_cmd(device, action='luksFormat', pbkdf='pbkdf2',pbkdf_force_iterations=1000,
                type='luks2',header=luks_header, luks2_keyslots_size='16352k', luks2_metadata_size='16k',offset=131072)
        self.run_cmd(action='luksDump', dmname=luks_header, set_passwd=False,)

        # 31
        self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, key_slot=5, spec=('-q', key5))

        self.run_cmd(device, action='luksAddKey', pbkdf='pbkdf2', key_file=key5,
                pbkdf_force_iterations=1000, key_slot=1,spec=('-q', key1))

        if self.check_options(self.cmd, '--dump-json-metadata') :
            self.run_cmd(device, action='luksDump',  spec=('-q', '--dump-json-metadata',), set_passwd=False, return_code=1)

        self.run_cmd(device, action='convert', type='luks1', set_passwd=False, return_code=1)
        self.run_cmd(device, action='luksDump',  set_passwd=False, grep='Key Slot 1: ENABLED')
        self.run_cmd(device, action='luksDump',  set_passwd=False, grep='Key Slot 5: ENABLED')
        self.run_cmd(device, action='convert', type='luks2', set_passwd=False,)
        self.run_cmd(device, action='luksDump',  set_passwd=False, grep='1: luks2')
        self.run_cmd(device, action='luksDump',  set_passwd=False, grep='5: luks2')
        self.run_cmd(device, action='convert', type='luks1', set_passwd=False,)

        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', sector_size=512,
                pbkdf_force_iterations=1000, key_slot=0, spec=('-q', key5), hash='sha512')
        self.run_cmd(device, action='luksAddKey', pbkdf='pbkdf2', key_file=key5, hash='sha512',
                pbkdf_force_iterations=1000, key_slot=1,spec=('-q', key1))
        self.run_cmd(device, action='convert', type='luks1', set_passwd=False,)
        self.run_cmd(device, action='luksKillSlot', set_passwd=False, spec=('-q', 1))
        self.run_cmd(device, action='convert', type='luks1', set_passwd=False, return_code=1,)
        self.run_cmd(device, action='luksDump',  set_passwd=False, grep='Key Slot 0: ENABLED')
        self.run_cmd(device, action='open',  set_passwd=False, spec=('-q', '--test-passphrase' ),key_slot=0, key_file=key5 )


        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', sector_size=1024,
                pbkdf_force_iterations=1000, spec=('-q', key5))
        self.run_cmd(device, action='convert', type='luks1', set_passwd=False, return_code=1)

        self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', align_payload=4097,
                pbkdf_force_iterations=1000, spec=('-q', key5))
        self.run_cmd(device, action='convert', type='luks2', set_passwd=False,)
        self.run_cmd(device, action='isLuks',  type='luks2', set_passwd=False,)
        self.run_cmd(device, action='open', set_passwd=False, key_slot=0, key_file=key5, spec=('-q', '--test-passphrase'))

        if self.dm_crypt_keyring_support() and self.dm_crypt_keyring_new_kernel():
            self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,  header=luks_header,)
            self.run_cmd(device, action='open', dmname=dmname, header=luks_header, )
            self.run_cmd(action='status', dmname=dmname, set_passwd=False,)
            self.run_cmd(action='status', dmname=dmname,  set_passwd=False, grep='keyring')
            self.remove_crypt(dmname)
            if self.run('rmmod dm-crypt') == 0 :
                self.run_cmd(device, action='open', dmname=dmname, header=luks_header, )
                self.run_cmd(action='status', dmname=dmname,  set_passwd=False, grep='keyring')
                self.remove_crypt(dmname)

                self.run_cmd(device, action='open', dmname=dmname, header=luks_header, spec=('-q', '--disable-keyring') )
                self.run_cmd(action='status', dmname=dmname, set_passwd=False,)
                self.run_cmd(action='status',  dmname=dmname, set_passwd=False, grep='dm-crypt')
                self.remove_crypt(dmname)

                self.run_cmd(device, action='open', dmname=dmname, header=luks_header, spec=('-q', '--disable-keyring') )
                self.run_cmd(action='luksSuspend', dmname=dmname, )
                self.run_cmd(action='luksResume', dmname=dmname, header=luks_header )
                self.run_cmd(action='status', dmname=dmname, set_passwd=False,)
                self.run_cmd(action='status', dmname=dmname,  grep='keyring')
                self.remove_crypt(dmname)

                self.run_cmd(device, action='open', dmname=dmname, header=luks_header,)
                self.run_cmd(action='luksSuspend', dmname=dmname,)
                self.run_cmd(action='luksResume', dmname=dmname, header=luks_header,spec=('-q','--disable-keyring'))
                self.run_cmd(action='status', dmname=dmname, set_passwd=False,)
                self.run_cmd(action='status', dmname=dmname,  grep='dm-crypt')
                self.remove_crypt(dmname)
                self.run('modprobe dm-crypt')
        # 33
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,)
        print(HAVE_KEYRING > 0)
        print(os.path.exists("/proc/sys/kernel/keys"))
        if (HAVE_KEYRING > 0) and os.path.exists("/proc/sys/kernel/keys"):
            self.test_and_prepare_keyring()
            self.run_cmd(device, action='token add',key_description=token0, token_id=3,set_passwd=False,)
            self.run_cmd(device, action='luksDump', grep='3: luks2-keyring', set_passwd=False,)
            self.run_cmd(device, action='token add',key_description=token1, key_slot=5,set_passwd=False, return_code=1)
            # RHEL8 return 1, RHEL9 return 2,so skip it
            #self.run_cmd(device, action='open',set_passwd=False,
            #        spec=('-q', '--token-only','--test-passphrase'), return_code=2)
            self.load_key("user %s %s %s" % (token0, 'wrong_passwd', self.test_keyring))
            self.run_cmd(device, action='open',set_passwd=False,
                    spec=('-q', '--token-only','--test-passphrase'), return_code=2)

            self.load_key("user %s '%s' %s" % (token0, self.passwd, self.test_keyring))

            self.run_cmd(device, action='open',dmname=dmname,
                    set_passwd=False, spec=('-q', '--token-only','--test-passphrase'))
            self.run_cmd(device, action='open', dmname=dmname,
                    set_passwd=False, spec=('-q', '--token-only',))

            self.run_cmd(action='status',dmname=dmname,set_passwd=False,)
            self.run_cmd(action='luksSuspend',dmname=dmname,set_passwd=False,)
            self.run_cmd(action='luksResume',dmname=dmname,)
            if self.check_options(self.cmd, '--token-type'):
                self.run_cmd(action='status',dmname=dmname,set_passwd=False, grep='suspended', return_code=1)
                self.run_cmd(action='luksSuspend',dmname=dmname,set_passwd=False,)
                self.run_cmd(action='luksResume',dmname=dmname,
                    token_type='luks2-keyring',)
            self.remove_crypt(dmname)

            if self.check_options(self.cmd, '--token-type'):
                cmd="echo -n '%s' | cryptsetup token import %s --token-id 22" % (IMPORT_TOKEN, device)
                if self.run(cmd) == 0 :
                    self.run_cmd(device, action='open', token_type='some_type',
                        spec=('--token-only', '--test-passphrase'), return_code=1)
                    self.run_cmd(device, action='open', token_type='some_type', dmname=dmname,
                        spec=('--token-only', ), return_code=1)
                    self.run_cmd(dmname=dmname, action='status', return_code=4,)
                else:
                    self._print("FAIL: import token %s" % IMPORT_TOKEN)

            self.run_cmd(device, action='token remove', token_id=3, set_passwd=False,)
            self.run_cmd(device, action='luksDump', grep='3: luks2-keyring', set_passwd=False, return_code=1)

            self.luks_add_key(device, old_key=self.passwd, new_key=new_one, key_slot=4,
                pbkdf='pbkdf2',pbkdf_force_iterations=1000,)
            self.run_cmd(device, action='token add',key_description=token1, key_slot=4, set_passwd=False,)
            self.run_cmd(device, action='luksKillSlot', set_passwd=False, spec=('-q', 4))

            cmd="echo -n '%s' | cryptsetup token import %s --token-id 10" % (IMPORT_TOKEN, device)
            if self.run(cmd) :
                self._print("FAIL: run cmd %s" % cmd)
            cmd="echo -n '%s' | cryptsetup token import %s --token-id 11  --json-file -" % (IMPORT_TOKEN, device)
            if self.run(cmd) :
                self._print("FAIL: run cmd %s" % cmd)
            test_token_file0 = '/tmp/tokenfile0'
            cmd="echo -n '%s' > %s" % (IMPORT_TOKEN, test_token_file0)
            self.run(cmd)
            self.run_cmd(device, action='token import', token_id=12, json_file=test_token_file0, set_passwd=False,)
            self.run_cmd(device, action='token import', token_id=12,
                    json_file=test_token_file0, set_passwd=False, return_code=1)
            export_token_0 = self.run_cmd(device, action='token export', token_id=10, set_passwd=False,)
            print(export_token_0)

        # LUKS keyslot priority
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, key_slot=1)
        self.luks_add_key(device, old_key=self.passwd, new_key=new_one, key_slot=5,
                pbkdf='pbkdf2',pbkdf_force_iterations=1000,)
        self.run_cmd(device, action='config',  key_slot=0, priority='prefer',
                return_code=1, set_passwd=False)
        self.run_cmd(device, action='config',  key_slot=1, priority='wrong',
                return_code=1, set_passwd=False)
        self.run_cmd(device, action='config',  key_slot=1, priority='ignore',
                set_passwd=False)
        self.run_cmd(device, action='open', spec=('-q', '--test-passphrase'),
                return_code=2,)
        self.run_cmd(device, action='open', spec=('-q', '--test-passphrase'),key_slot=1,)
        self.run_cmd(device, action='open', spec=('-q', '--test-passphrase'), set_passwd=new_one)


        self.run_cmd(device, action='config',  key_slot=1, priority='normal',
                set_passwd=False)
        self.run_cmd(device, action='open', spec=('-q', '--test-passphrase'))
        self.run_cmd(device, action='config',  key_slot=1, priority='ignore',
                set_passwd=False)
        self.run_cmd(device, action='open', spec=('-q', '--test-passphrase'), return_code=2)




        # luks pbkdf setting
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdfXX', return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=999, return_code=1,)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1234,)
        self.run_cmd(device, action='luksDump', grep='1234', set_passwd=False,)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='argon2id',
                pbkdf_force_iterations=3, return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='argon2id',
                pbkdf_force_iterations=4, pbkdf_memory=100000, ignore_failed='get_fips',)

        self.run_cmd(device, action='luksDump', grep='argon2id', set_passwd=False, ignore_failed='get_fips')

        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='argon2i',
                pbkdf_force_iterations=4, pbkdf_memory=1234, pbkdf_parallel=1 ,ignore_failed='get_fips' )
        self.run_cmd(device, action='luksDump', grep='argon2i', set_passwd=False, ignore_failed='get_fips')
        self.run_cmd(device, action='luksDump', grep='Time cost: 4', set_passwd=False,ignore_failed='get_fips' )
        self.run_cmd(device, action='luksDump', grep='Memory: 1234', set_passwd=False, ignore_failed='get_fips')
        self.run_cmd(device, action='luksDump', grep='Threads: 1', set_passwd=False,ignore_failed='get_fips')


        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='argon2i',
                pbkdf_force_iterations=4, pbkdf_memory=1234, pbkdf_parallel=1 ,ignore_failed='get_fips' )

        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                iter_time=500,)



        # LUKS Keyslot convert
        self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2',  spec=('-q', key5),
                pbkdf_force_iterations=1000, key_slot=5, set_passwd=False,)
        self.run_cmd(device, action='luksConvertKey', key_file=key5, set_passwd=False, return_code=1)
        self.run_cmd(device, action='convert', type='luks2', set_passwd=False,)
        self.run_cmd(device, action='luksDump', grep='5: luks2', set_passwd=False,)
        self.run_cmd(device, action='luksDump', grep='pbkdf2', set_passwd=False,)
        self.run_cmd(device, action='luksConvertKey', key_file=key5, key_slot=5, pbkdf='argon2i',
                set_passwd=False, pbkdf_memory=32,  iter_time=1, ignore_failed='get_fips' )

        self.run_cmd(device, action='luksDump', grep='5: luks2', set_passwd=False,)
        self.run_cmd(device, action='luksAddKey', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                key_slot=1, key_file=key5, )

        self.run_cmd(device, action='luksDump', grep='5: luks2', set_passwd=False,)
        self.run_cmd(device, action='luksKillSlot', set_passwd=False, spec=('-q', 5))
        self.run_cmd(device, action='luksDump', grep='1: luks2', set_passwd=False,)
        self.run_cmd(device, action='luksDump', grep='pbkdf2', set_passwd=False,)

        self.run_cmd(device, action='luksConvertKey', key_slot=1, pbkdf='argon2i',
                 pbkdf_memory=32,  iter_time=1, ignore_failed='get_fips' )

        self.run_cmd(device, action='luksDump', grep='1: luks2', set_passwd=False, ignore_failed='get_fips')

        self.run_cmd(device, action='luksAddKey', pbkdf='pbkdf2' ,set_passwd='passwdpasswd',
                pbkdf_force_iterations=1000,  key_slot=21, key_size=16, spec=('-q', '--unbound'))
        self.run_cmd(device, action='luksConvertKey', pbkdf='pbkdf2', key_slot=21, set_passwd='passwdpasswd',
                  pbkdf_force_iterations=1001,)


        # luksAddkey unbound tests
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',  spec=('-q', key5),
                pbkdf_force_iterations=1000, key_slot=5, set_passwd=False,)
        self.run_cmd(device, action='luksAddKey', pbkdf='pbkdf2' ,
                pbkdf_force_iterations=1000,  key_size=16, spec=('-q', '--unbound'))
        self.run_cmd(device, action='luksAddKey', pbkdf='pbkdf2' ,set_passwd=new_one,
                pbkdf_force_iterations=1000,  key_slot=2, key_size=32, spec=('-q', '--unbound'))
        self.run_cmd(device, action='luksDump', grep='2: luks2 (unbound)',set_passwd=False )


        self.run_cmd(device, action='luksAddKey', key_slot=5, spec=('-q', '--unbound'), key_size=32, return_code=1,)
        self.run_cmd(device, action='open',  dmname=dmname, return_code=1, set_passwd=new_one,)
        self.run_cmd(device, action='open',  dmname=dmname, key_slot=2, return_code=1, set_passwd=new_one,)
        self.run_cmd(device, action='open',  dmname=dmname, return_code=1,)


        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2',
                pbkdf_force_iterations=1000,)
        self.run_cmd(device, action='luksFormat', type='luks1', pbkdf='pbkdf2', key_size=256, luks2_metadata_size='128k',
                luks2_keyslots_size='128k',pbkdf_force_iterations=1000, return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256, luks2_metadata_size='128k',
                luks2_keyslots_size='127k',pbkdf_force_iterations=1000, return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256, luks2_metadata_size='127k',
                luks2_keyslots_size='128k',pbkdf_force_iterations=1000, return_code=1)

        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256, luks2_metadata_size='128k',
                luks2_keyslots_size='128M',pbkdf_force_iterations=1000,)

        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256, luks2_metadata_size='128k',
                luks2_keyslots_size='128k',pbkdf_force_iterations=1000,)

        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256, luks2_metadata_size='128k',
                pbkdf_force_iterations=1000,)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256,
                luks2_keyslots_size='128k',pbkdf_force_iterations=1000)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256,
                offset=16384,pbkdf_force_iterations=1000)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256, offset=64,
                luks2_keyslots_size=8192, pbkdf_force_iterations=1000, return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256, offset=64+56,
                luks2_keyslots_size=8192, pbkdf_force_iterations=1000, return_code=1)
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', key_size=256, offset=64+64,
                luks2_keyslots_size=8192, pbkdf_force_iterations=1000, return_code=1)

        # Per-keyslot encrypttion parameters
        keyslot_cipher='aes-cbc-plain64'
        self.run_cmd(device, action='luksFormat', type='luks2', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                spec=('-q', key1), key_slot=0, keyslot_cipher=keyslot_cipher, keyslot_key_size=128)

        self.run_cmd(device, action='luksAddKey', key_file=key1, spec=('-q', key2), pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, key_slot=1, keyslot_cipher=keyslot_cipher, keyslot_key_size=128   )

        self.run_cmd(device, action='luksAddKey', key_file=key1, spec=('-q', key2), pbkdf='pbkdf2',
                pbkdf_force_iterations=1000, key_slot=2,)

        self.run_cmd(device, action='luksChangeKey', key_file=key2, spec=('-q', key1), pbkdf='pbkdf2',
                keyslot_cipher=keyslot_cipher, keyslot_key_size=128,
                pbkdf_force_iterations=1000, key_slot=2,  )

        self.run_cmd(device, action='luksAddKey',  spec=('-q', '--unbound'), pbkdf='pbkdf2', set_passwd='passwdpasswd',
                keyslot_cipher=keyslot_cipher, keyslot_key_size=128,
                pbkdf_force_iterations=1000, key_slot=21, key_size=32, )

        self.run_cmd(device, action='luksAddKey', pbkdf='pbkdf2',
                key_slot=22, key_size=32, spec=('-q', '--unbound'), set_passwd='passwdpasswd')

        self.run_cmd(device, action='luksConvertKey', pbkdf='pbkdf2', pbkdf_force_iterations=1000,
                keyslot_cipher=keyslot_cipher, keyslot_key_size=128,
                key_slot=22, set_passwd='passwdpasswd' )

       # 42
        ciphers = ['aes-ecb', 'aes-cbc-null', 'aes-cbc-plain64', 'aes-cbc-essiv:sha256', 'aes-xts-plain64']
        for cipher in ciphers:
           self._print("INFO: %s-256" % cipher)
           self.run_cmd(device, action='luksFormat',type='luks2', spec=('-q', key1), pbkdf='pbkdf2',
                   pbkdf_force_iterations=1000, cipher=cipher, key_size=256,)





