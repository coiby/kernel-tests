#!/usr/bin/env python
# -*- coding: utf-8 -*-

from libsan.host.cmdline import run
import libsan.host.linux as linux
import argparse
import stqe.host.tc
import sys

# --kernel_ops=scsi_mod.use_blk_mq=1,test1=1

def add_param_to_kernel(param):
    default_kernel = run("grubby --default-kernel")
    cmd = "grubby --args ' %s ' --update-kernel %s " % (param, default_kernel)
    ret, out = run(cmd, return_output=True, verbose=False)
    if ret != 0:
        print("add %s to %s failed" % (param, default_kernel))
        return False
    return True

def main():
    parser = argparse.ArgumentParser(description='add_param_to_kernel')
    parser.add_argument(
        "--kernel_ops",
        "-k",
        required=False,
        dest="kernel_ops",
        nargs="?",
        help="kernel parameter",
        metavar="kernel_ops")
    args = parser.parse_args()
    print("the kernel_ops is %s" % args.kernel_ops)
    if args.kernel_ops:
        opss = args.kernel_ops.split(",")
        for line in opss:
            print("will add %s to kernel" % line)
            if add_param_to_kernel(line):
                print("add kernel paramter %s successful,but need reboot" %line)
            else:
                print("FAIL add kernel paramter %s" % line)
                return False
    else:
        print("the args is None, please add one args to kernel ")
        return False

if __name__ == '__main__':
    global TestObj
    TestObj = stqe.host.tc.TestClass()
    print(linux.kernel_command_line())
    main()
    sys.exit(0)
