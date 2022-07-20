#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import absolute_import, division, print_function, unicode_literals
__author__ = "Guazhang"
__copyright__ = "Copyright (c) 2016 Red Hat, Inc. All rights reserved."



import os
import libsan.host.linux as linux
from luks import Luks
from luks_luks1 import crypt_luks1
from luks_luks2 import crypt_luks2
from luks_bugs import crypt_bugs
from luks_validation import luks_integrity
from luks_reencrypt import reencrypt
import shutil


class Test_Crypt(crypt_luks1, crypt_luks2, crypt_bugs,luks_integrity,reencrypt ):
    def __init___(self,):
        supper().__init__(self,)

    def cleanup(self,):
        shutil.rmtree("/tmp/")
        os.mkdir('/tmp/')




#https://github.com/storaged-project/libblockdev/blob/master/tests/crypto_test.py

if __name__ == "__main__" :
    obj=Test_Crypt()
    obj.crypt_luks1_tests = ['compat_test',]
    obj.crypt_luks2_tests = ['compat_test2',]
    #obj.crypt_bugs_tests = ['test_luks', 'luks_bz1862173','luks_passphrases',
    obj.crypt_bugs_tests = ['test_luks', 'luks_passphrases','luks_paramter','luks_bz1750680','luks_bz2073433','luks_conversion',
                'integrity_setup','reencrypt_online' ]
    obj.crypt_integrity_test = ['dm_integrity_format', 'integrity_error_detection',
            'integrity_int_journal','integrity_int_journal_crypt', 'integrity_int_mode','feature_test','integrity_resize']
    obj.crypt_reencrypt = ['reencrypt_test','reencrypt_data_shift', 'reencrypt_with_header']

    obj.force_clean_up()
    obj.cleanup()
    os.environ["LVM_SUPPRESS_FD_WARNINGS"] = "1"
    #keys = ["vdo","nvme","part","raid","stratis","lvm" ,"dm"]
    new_target = os.getenv("target_type")

    case_name = os.getenv("case_name")

    # "crypt_luks1_tests crypt_luks2_tests  crypt_bugs_tests crypt_integrity_test"
    crypt_type = os.getenv("crypt_type")

    # don't run case in some type
    non_case = os.getenv('non_case')

    full_case = obj.crypt_luks1_tests + obj.crypt_luks2_tests +\
            obj.crypt_bugs_tests + obj.crypt_integrity_test + obj.crypt_reencrypt

    if new_target:
        obj.target_type = new_target.split()

    if case_name :
        case_name = case_name.split()

    if crypt_type :
        if not case_name :
            case_name = []
        for t in crypt_type.split():
            if hasattr(obj, t):
                for i in getattr(obj, t):
                    if i not in case_name :
                        case_name.append(i)

    if (not case_name) and (not crypt_type) :
        case_name = obj.crypt_bugs_tests

    if non_case :
        for i in non_case.split():
            if i in case_name :
                case_name.remove(i)

    for case in case_name :
        if case not in full_case :
            print("FAIL: the case name %s  is not in full case list %s" % (case, full_case))
            print("\n please input case name ")
            exit(1)


    obj._print("INFO: get new_target %s" % new_target)
    obj._print("INFO: we will test case %s " % case_name)
    obj.fs="xfs"
    obj.run("lsblk")
    keys = obj.target_type
    for i in keys:
        target = obj.make_test_target(i)
        if not target :
            obj._print("FAIL : Could not get target with %s" % i)
            continue
        obj.run("lsblk")
        obj._print("INFO: will test %s %s" % (i,target ))
        obj.device_type = i
        for c in case_name:
            if hasattr(obj, c):
                obj._print("INFO: ######### we start test the case %s for %s deivce %s now ############" % (c, i, target))
                getattr(obj, c)(target)
                obj._print("INFO: ######### we finished test the case %s for %s deivce %s now ############" % (c, i, target))
        print(obj.force_clean_up())
    obj.run("lsblk")
    obj.force_clean_up()
    print('#'*100)
    print(obj.error_message)
    print('#'*100)
    if obj.error_message:
        exit(1)

