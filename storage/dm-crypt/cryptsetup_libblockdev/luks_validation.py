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
import libsan.host.linux as linux

from luks import Luks

class luks_integrity(Luks):
    def __init___(self,):
        supper().__init__(self,)
        self.cmd = 'integritysetup'

    def check_feature(self,):
        feature = []
        self.run('modprobe dm-integrity')
        ret, ver_str = self.run("dmsetup targets | grep integrity | cut -f2 -dv",True)
        ver = ver_str.split('.')
        ver_maj = int(ver[0])
        ver_min = int(ver[1])
        ver_ptc = int(ver[2])
        print((ver_min > 5) and (not self.run('integritysetup --help | grep resize')))
        if ver_maj < 1 :
            return False
        if ver_min > 1:
            feature.append('DM_INTEGRITY_META')
            feature.append('DM_INTEGRITY_RECALC')
        if ver_min > 2 :
            feature.append('DM_INTEGRITY_BITMAP')
        if (ver_min > 5) and (not self.run('integritysetup --help | grep resize')):
            feature.append('DM_INTEGRITY_RESIZE_SUPPORTED')
        if ver_min > 6 :
            feature.append('DM_INTEGRITY_HMAC_FIX')
        if ver_min > 7 and (not self.run('integritysetup --help | grep resize')):
            feature.append('DM_INTEGRITY_RESET')
        self._print("INFO: integrity feature %s" % feature)
        return feature


    def dm_integrity_format(self, device):
        self.cmd = 'integritysetup'
        dmname = self.range_str(10)
        keyfile = self.luks_keyfile(4096)
        def initformat(alg, tagsize, check_tag_size, sector, keyfile=None, keysize=None,):
            d_key = {}
            d_tag = {}
            if keysize :
                d_key['integrity_key_file'] = keyfile
                d_key['integrity_key_size'] = keysize
            if tagsize != 0:
                d_tag['tag_size'] = tagsize

            if d_key :
                d_tag.update(d_key)

            self.run_cmd(device, action='format', spec=('--integrity-legacy-padding', '-q'),
                    set_passwd=False, integrity=alg,sector_size=sector , **d_tag)

            self.run_cmd(device, action='dump', set_passwd=False,)
            self.run_cmd(device, action='dump', grep='tag_size %s' % check_tag_size, set_passwd=False,)
            self.run_cmd(device, action='dump', grep='sector_size %s' % sector, set_passwd=False,)

            self.run_cmd(device, action='open', dmname=dmname,  integrity=alg, set_passwd=False, **d_key,)
            ret, vsum1 = self.run("sha256sum /dev/mapper/%s" % dmname, True)
            self.run_cmd(action='status', dmname=dmname,set_passwd=False,)
            self.run_cmd(action='status', dmname=dmname, grep='tag size: %s' % check_tag_size,set_passwd=False,)
            self.run_cmd(action='status', dmname=dmname, grep='integrity: %s' %  alg.split('-')[0] if '-' in alg else alg ,
                    set_passwd=False,)
            self.run_cmd(action='status', dmname=dmname, grep='sector size:  %s bytes' % sector, set_passwd=False,)

            self.run('dd if=/dev/zero of=/dev/mapper/%s bs=1M oflag=direct' % dmname, False,False)
            self.run('dmsetup remove --retry %s' % dmname,False,False)
            self.run_cmd(device, action='open', dmname=dmname,  integrity=alg, set_passwd=False, **d_key)
            ret, vsum2 = self.run("sha256sum /dev/mapper/%s" % dmname, True)
            if vsum1 != vsum2 :
                self._print("FAIL: the dm checksum failed")
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)

        #initformat('blake2s-256', 32, 32, 512)
        #initformat('blake2b-256', 32, 32, 512)

        #initformat('crc32c', 0, 4, 512)
        #initformat('crc32', 0, 4, 512)
        #initformat('sha1', 0, 20, 512)
        #initformat('sha1', 16, 16, 4096)
        #initformat('sha256', 0, 32, 512)
        initformat('hmac-sha256', 0, 32, 512, keyfile, 32)
        initformat('sha256', 0, 32, 4096)
        initformat('hmac-sha256', 0, 32, 4096, keyfile, 32)
        initformat('hmac-sha256', 0, 32, 4096, keyfile, 4096)


    def integrity_error_detection(self, device):
        self.cmd = 'integritysetup'
        dmname = self.range_str(10)
        keyfile = self.luks_keyfile(4096)

        def init_error(mode, alg, tagsize, check_tag_size, sector, keyfile=None, keysize=None,):
            INT_MODE=''
            if mode =='B':
                INT_MODE='-B'
            d_key = {}
            d_tag = {}
            if keysize :
                d_key['integrity_key_file'] = keyfile
                d_key['integrity_key_size'] = keysize
            if tagsize != 0:
                d_tag['tag_size'] = tagsize

            if d_key :
                d_tag.update(d_key)


            self.run('dd if=/dev/zero of=%s bs=1M count=32' % device)
            self.run_cmd(device, action='format', spec=(INT_MODE, '-q'),
                    set_passwd=False, integrity=alg,sector_size=sector,**d_tag)

            self.run_cmd(device, action='open', dmname=dmname,  integrity=alg,
                    set_passwd=False, spec=('--integrity-no-journal','-q',INT_MODE, ), **d_key)
            if d_key:
                ret,key_hex=self.run('xxd -c 256 -l %s -p %s' % (keysize, keyfile), True)
                if key_hex:
                    self.run('dmsetup table --showkeys %s | grep -q %s' % (dmname, key_hex))
            write_code = "EXAMPLETEXT"
            self.run("echo -n %s |dd of=/dev/mapper/%s" % (write_code, dmname))
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)
            ret,off_hex=self.run("dd if=%s bs=512 2>/dev/null |hexdump -C | grep %s" % (device, write_code), True)
            off_dex = int(str(off_hex.split()[0]),16)
            wrong_code='Z'
            self.run("echo -n %s | dd of=%s bs=1 seek=%s conv=notrunc >/dev/null" % (wrong_code, device, off_dex))
            self.run_cmd(device, action='open', dmname=dmname, integrity=alg,
                    set_passwd=False, spec=('--integrity-no-journal','-q',INT_MODE,), **d_key)
            ret, out = self.run("dd if=/dev/mapper/%s  >/dev/null" % dmname,True)
            if ret == 0:
                self._print("FAIL: Could not get error in the device")
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)
        init_error('J', 'crc32c', 0, 4, 512, )
        init_error('J', 'crc32c', 0, 4, 4096, )
        init_error('J', 'crc32', 0, 4, 512, )
        init_error('J', 'crc32', 0, 4, 4096, )
        init_error('J', 'sha1', 0, 20, 512, )
        init_error('J', 'sha1', 16, 16, 512, )
        init_error('J', 'sha1', 0, 20, 4096, )
        init_error('J', 'sha256', 0, 32, 512, )
        init_error('J', 'sha256', 0, 32, 4096, )
        init_error('J', 'hmac-sha256', 0, 32, 512, keyfile,32 )
        init_error('J', 'hmac-sha256', 0, 32, 4096, keyfile,32 )
        feas = self.check_feature()
        if 'DM_INTEGRITY_BITMAP' in feas :
            init_error('B', 'crc32c', 0, 4, 512,)
            init_error('B', 'crc32c', 0, 4, 4096,)
            init_error('B', 'sha256', 0, 32, 512,)
            init_error('B', 'sha256', 0, 32, 4096,)
            init_error('B', 'hmac-sha256', 0, 32, 512, keyfile,32 )
            init_error('B', 'hmac-sha256', 0, 32, 4096, keyfile,32 )




    def integrity_int_journal(self, device):
        self.cmd = 'integritysetup'
        dmname = self.range_str(10)
        keyfile = self.luks_keyfile(4096)

        def init_journal(alg, tagsize, sector, watermark, commit_time,
                journal_integrity, key_file, key_size, journal_integrity_out):
            self.run_cmd(device, action='format', set_passwd=False,
                    integrity=alg, sector_size=sector, tag_size=tagsize, journal_watermark=watermark,
                    journal_commit_time=commit_time, journal_integrity=journal_integrity,
                    journal_integrity_key_file=key_file, journal_integrity_key_size=key_size)

            self.run_cmd(device, action='open', dmname=dmname,  integrity=alg,
                    set_passwd=False,  journal_watermark=watermark,
                    journal_commit_time=commit_time, journal_integrity=journal_integrity,
                    journal_integrity_key_file=key_file, journal_integrity_key_size=key_size,)

            ret,key_hex=self.run('xxd -c 4096 -l %s -p %s' % (key_size, key_file), True)
            if key_hex:
                self.run('dmsetup table --showkeys %s | grep -q %s' % (dmname, key_hex))
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)

        # Watermark is calculated in kernel, so it can be rounded down/up
        init_journal('crc32', 4, 512, 66, 1000, 'hmac-sha256', keyfile, 32, 'hmac\(sha256\)')
        init_journal('sha256', 32, 4096, 34, 5000, 'hmac-sha1', keyfile, 16, 'hmac\(sha1\)')
        init_journal('sha1', 20, 512,  75, 9999, 'hmac-sha256', keyfile, 32, 'hmac\(sha256\)')
        init_journal('sha1',   20, 512,  75, 9999, 'hmac-sha256', keyfile, 4096, 'hmac\(sha256\)')

    def integrity_int_journal_crypt(self, device):
        self.cmd = 'integritysetup'
        dmname = self.range_str(10)
        keyfile = self.luks_keyfile(4096)

        def int_journal_crypt(alg, alg_kernel, keyfile, keysize ):
            self.run_cmd(device, action='format', set_passwd=False,
                    journal_crypt=alg, journal_crypt_key_file=keyfile, journal_crypt_key_size=keysize)

            self.run_cmd(device, action='open', set_passwd=False, dmname=dmname,
                    journal_crypt=alg, journal_crypt_key_file=keyfile, journal_crypt_key_size=keysize)

            ret,key_hex=self.run('xxd -c 256 -l %s -p %s' % (keysize, keyfile), True)
            if key_hex:
                self.run('dmsetup table --showkeys %s | grep -q "%s:%s"' % (dmname, alg_kernel,key_hex))
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)


        int_journal_crypt('cbc-aes', 'cbc\(aes\)', keyfile, 32)
        int_journal_crypt('cbc-aes', 'cbc\(aes\)', keyfile, 16)
        int_journal_crypt('ctr-aes', 'ctr\(aes\)', keyfile, 32)
        int_journal_crypt('ctr-aes', 'ctr\(aes\)', keyfile, 16)

    def integrity_int_mode(self, device):
        self.cmd = 'integritysetup'
        dmname = self.range_str(10)
        keyfile = self.luks_keyfile(4096)

        def int_mode(alg, tagsize, sector,keyfile=None,keysize=None):
            key_params=''
            if keysize :
                key_params="--integrity-key-file %s --integrity-key-size %s" % (keyfile, keysize)

            d_key = {}
            if keysize :
                d_key['integrity_key_file'] = keyfile
                d_key['integrity_key_size'] = keysize

            self.run_cmd(device, action='format', set_passwd=False,
                    integrity=alg, tag_size=tagsize, sector_size=sector, **d_key)
            self.run_cmd(device, action='open', set_passwd=False, dmname=dmname,
                    integrity=alg, **d_key)
            self.run_cmd(action='status', dmname=dmname, set_passwd=False,)
            self.run_cmd(action='status', dmname=dmname, grep='read/write', set_passwd=False,)
            ret, out=self.run('dmsetup table --showkeys %s' % dmname,True )
            print(out.split()[0:10])
            if ret == 0:
                if out.split()[6] != 'J':
                    self._print("FAIL: the dmsetup table show status J is not right")
            else:
                self._print("FAIL: Could not get dmsetup table")

            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)

            self.run_cmd(device, action='open', set_passwd=False, dmname=dmname,
                    integrity=alg,spec=('-q','--integrity-no-journal'),**d_key)

            self.run_cmd(action='status', dmname=dmname,  set_passwd=False,)
            self.run_cmd(action='status', dmname=dmname, grep='read/write', set_passwd=False,)
            self.run_cmd(action='status', dmname=dmname, grep='not active', set_passwd=False,)
            ret, out=self.run('dmsetup table --showkeys %s' % dmname,True )
            print(out.split()[0:10])
            if ret == 0:
                if out.split()[6] != 'D':
                    self._print("FAIL: the dmsetup table show status  D is not right")
            else:
                self._print("FAIL: Could not get dmsetup table")
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)

            self.run_cmd(device, action='open', set_passwd=False, dmname=dmname,
                    integrity=alg,spec=('-q','--integrity-recovery-mode'),**d_key)
            self.run_cmd(action='status', dmname=dmname, set_passwd=False,)
            self.run_cmd(action='status', dmname=dmname, grep='read/write recovery', set_passwd=False,)
            ret, out=self.run('dmsetup table --showkeys %s' % dmname,True )
            print(out.split()[0:10])
            if ret == 0:
                if out.split()[6] != 'R':
                    self._print("FAIL: the dmsetup table show status  R is not right")
            else:
                self._print("FAIL: Could not get dmsetup table")
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)

        int_mode('crc32c',4,512)
        int_mode('crc32',4,512)
        int_mode('sha1',20, 512)
        int_mode('sha256',32, 512)
        int_mode('hmac-sha256', 32, 512,  keyfile, 32)
        int_mode('hmac-sha256', 32, 4096, keyfile, 32)


    def feature_test(self, device):
        self.cmd = 'integritysetup'
        dmname = self.range_str(10)
        keyfile = self.luks_keyfile(4096)
        keyfile1 = self.luks_keyfile(32)
        feas = self.check_feature()
        self._print("INFO: the feature is %s" % feas)
        self.dev2 = "/dev/%s" % self.add_loop()
        if 'DM_INTEGRITY_RECALC' in feas :
            self.run_cmd(device, action='format', spec=('-q', '--no-wipe'), set_passwd=False,)
            self.run_cmd(device, action='open', dmname=dmname, spec=('-q', '--integrity-recalculate'),
                    set_passwd=False)
            ret, vsum1 = self.run('sha256sum /dev/mapper/%s' % dmname, True)
            self.run('dd if=/dev/mapper/%s of=/dev/null bs=1M' % dmname)
            ret, vsum2 = self.run('sha256sum /dev/mapper/%s' % dmname, True)
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)
            if vsum1 != vsum2 :
                self._print("FAIL: the vsum is diff after run dd")
            if 'DM_INTEGRITY_RESET' in feas :
                self.run_cmd(device, action='open', dmname=dmname, spec=('-q', '--integrity-recalculate-reset'),
                    set_passwd=False, integrity='sha256')
                self.run('dd if=/dev/mapper/%s of=/dev/null bs=1M' % dmname)
                ret, vsum3 = self.run('sha256sum /dev/mapper/%s' % dmname, True)
                self.run_cmd(action='close', dmname=dmname, set_passwd=False,)
                if vsum1 != vsum3 :
                    self._print("FAIL: the vsum is diff after run reset")

        if 'DM_INTEGRITY_META' in feas :
            self.run_cmd(device, action='format', data_device=self.dev2, set_passwd=False,)
            self.run_cmd(device, action='open', dmname=dmname, data_device=self.dev2,
                    set_passwd=False)
            self.run_cmd(action='status', dmname=dmname, grep='metadata device:', set_passwd=False,)
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)

        if 'DM_INTEGRITY_BITMAP' in feas:
            self.run_cmd(device, action='format',spec=('-q', '--integrity-bitmap-mode', self.dev2),set_passwd=False,)

            self.run_cmd(device, action='open', dmname=dmname,bitmap_sectors_per_bit=65536,
                    bitmap_flush_time=5000, spec=('-q', '--integrity-bitmap-mode'), set_passwd=False)
            self.run_cmd(action='status', dmname=dmname, grep='bitmap 512-byte sectors per bit: 65536', set_passwd=False,)
            self.run_cmd(action='status', dmname=dmname, grep='bitmap flush interval: 5000 ms', set_passwd=False,)
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)



        if 'DM_INTEGRITY_HMAC_FIX' in feas :
            self.run_cmd(device, action='format',  set_passwd=False, spec=('-q',  '--integrity-legacy-hmac', '--no-wipe' ),
                    tag_size=32, integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,)
            self.run_cmd(device, action='open', dmname=dmname,spec=('-q', '--integrity-recalculate'), set_passwd=False,
                    integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,return_code=1,)
            self.run_cmd(device, action='open', dmname=dmname,spec=('-q', '--integrity-legacy-recalculate'), set_passwd=False,
                    integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,)
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)

            self.run_cmd(device, action='format',  set_passwd=False, spec=('-q', '--no-wipe' ),
                    tag_size=32, integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,)
            self.run_cmd(device, action='open', dmname=dmname,spec=('-q', '--integrity-recalculate'), set_passwd=False,
                    integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,return_code=1,)
            self.run_cmd(device, action='open', dmname=dmname,spec=('-q', '--integrity-legacy-recalculate'), set_passwd=False,
                    integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,)
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)


            self.run_cmd(device, action='format',  set_passwd=False, spec=('-q', '--no-wipe','--integrity-legacy-hmac' ),
                    tag_size=32, integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,
                    journal_integrity='hmac-sha256',journal_integrity_key_file=keyfile1,journal_integrity_key_size=32
                    )
            self.run_cmd(device, action='open', dmname=dmname,spec=('-q', '--integrity-recalculate'), set_passwd=False,
                    integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,
                    journal_integrity='hmac-sha256',journal_integrity_key_file=keyfile1,journal_integrity_key_size=32,
                    return_code=1)

            self.run_cmd(device, action='open', dmname=dmname,spec=('-q', '--integrity-legacy-recalculate'), set_passwd=False,
                    integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,
                    journal_integrity='hmac-sha256',journal_integrity_key_file=keyfile1,journal_integrity_key_size=32,)

            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)


            self.run_cmd(device, action='format',  set_passwd=False, spec=('-q', '--no-wipe',),
                    tag_size=32, integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,
                    journal_integrity='hmac-sha256',journal_integrity_key_file=keyfile1,journal_integrity_key_size=32
                    )
            self.run_cmd(device, action='dump', grep='fix_hmac', set_passwd=False,)
            self.run_cmd(device, action='open', dmname=dmname,spec=('-q', '--integrity-recalculate'), set_passwd=False,
                    integrity='hmac-sha256', integrity_key_file=keyfile, integrity_key_size=32,
                    journal_integrity='hmac-sha256',journal_integrity_key_file=keyfile1,journal_integrity_key_size=32,)
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)

        if not self.run('integritysetup --help | grep resize', False, False):
            self.run_cmd(device, action='format',  set_passwd=False, integrity='crc32',)
            self.run_cmd(device, action='open',  dmname=dmname, set_passwd=False, integrity='crc32',)
            self.run_cmd("/dev/mapper/%s" % dmname, action='resize', set_passwd=False, integrity='crc32',
                device_size='8MiB',)

            self.run_cmd(device, action='format',  set_passwd=False, integrity='hmac-sha256', integrity_key_size=128,
            integrity_key_file=keyfile, journal_integrity='hmac-sha256',journal_integrity_key_file=keyfile,
            journal_integrity_key_size=128, journal_crypt='ctr-aes', journal_crypt_key_size=16,journal_crypt_key_file=keyfile)

            self.run_cmd(device, action='open',  set_passwd=False, dmname=dmname, integrity='hmac-sha256', integrity_key_size=128,
            integrity_key_file=keyfile, journal_integrity='hmac-sha256',journal_integrity_key_file=keyfile,
            journal_integrity_key_size=128, journal_crypt='ctr-aes', journal_crypt_key_size=16,journal_crypt_key_file=keyfile)

            self.run_cmd("/dev/mapper/%s" %  dmname, action='resize', set_passwd=False, integrity='crc32',
                device_size='8MiB',)





    def integrity_resize(self,device):
        self.cmd = 'integritysetup'
        dmname = self.range_str(10)
        keyfile = self.luks_keyfile(4096)
        feas = self.check_feature()
        if not hasattr(self, 'dev2') :
            self.dev2 = "/dev/%s" % self.add_loop()

        def test_resize(detached_metadata, wipe, args ):
            if 'DM_INTEGRITY_RESIZE_SUPPORTED' not in feas :
                return False
            wipe_flag=''
            if wipe :
                wipe_flag='--wipe'

            if detached_metadata :
                self.run_cmd(self.dev2, action='format', data_device=device, **args,  set_passwd=False,)
                self.run_cmd(self.dev2, action='open', dmname=dmname, data_device=device, **args,
                    set_passwd=False)
            else:
                self.run_cmd(device, action='format', **args,  set_passwd=False,)
                self.run_cmd(device, action='open', dmname=dmname, **args,
                    set_passwd=False)
            self.run_cmd("/dev/mapper/%s" % dmname, action='resize', set_passwd=False, spec=('-q', wipe_flag,),
                device_size='1MiB',)
            self.run('dd if=/dev/mapper/%s' % dmname, False, False)
            self.run_cmd("/dev/mapper/%s" % dmname, action='resize', set_passwd=False, spec=('-q', wipe_flag,),
                device_size=0,)
            self.run('dd if=/dev/mapper/%s' % dmname, False, False)
            self.run_cmd(action='close', dmname=dmname, set_passwd=False,)

        test_resize(0, 0, {'integrity':'crc32'})
        test_resize(0, 1, {'integrity':'crc32'})
        test_resize(1, 0, {'integrity':'crc32'})
        test_resize(1, 1, {'integrity':'crc32'})
        if 'DM_INTEGRITY_HMAC_FIX' in feas :
            test_resize(0, 0, {'integrity':'hmac-sha256', 'integrity_key_size':128, 'integrity_key_file':keyfile,
                'journal_integrity':'hmac-sha256', 'journal_integrity_key_file':keyfile, 'journal_integrity_key_size':128,
                'journal_crypt':'ctr-aes', 'journal_crypt_key_size':16, 'journal_crypt_key_file':keyfile})

            test_resize(0, 1, {'integrity':'hmac-sha256', 'integrity_key_size':128, 'integrity_key_file':keyfile,
                'journal_integrity':'hmac-sha256', 'journal_integrity_key_file':keyfile, 'journal_integrity_key_size':128,
                'journal_crypt':'ctr-aes', 'journal_crypt_key_size':16, 'journal_crypt_key_file':keyfile})

            test_resize(1, 0, {'integrity':'hmac-sha256', 'integrity_key_size':128, 'integrity_key_file':keyfile,
                'journal_integrity':'hmac-sha256', 'journal_integrity_key_file':keyfile, 'journal_integrity_key_size':128,
                'journal_crypt':'ctr-aes', 'journal_crypt_key_size':16, 'journal_crypt_key_file':keyfile})

            test_resize(1, 1, {'integrity':'hmac-sha256', 'integrity_key_size':128, 'integrity_key_file':keyfile,
                'journal_integrity':'hmac-sha256', 'journal_integrity_key_file':keyfile, 'journal_integrity_key_size':128,
                'journal_crypt':'ctr-aes', 'journal_crypt_key_size':16, 'journal_crypt_key_file':keyfile})






