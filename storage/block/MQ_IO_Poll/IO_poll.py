#!/usr/bin/env python
# -*- coding: utf-8 -*-

import libsan.host.linux as linux
import time

def get_nvme_disk():
    ret,out=linux.run("lsblk |grep nvme  | awk '{print $1}'| head -1",True,True)
    print("the disk %s , ret is %s" % (out,ret))
    if ret :
        print("FAIL : Could not get the nvme disk %s" % out)
        return False
    return out

def fio_io_poll(disk):
    if not linux.install_package("fio"):
        print("FAIl : install fio failed ")
        exit(1)
    if linux.run("fio --parse-only --name=test --ioengine=pvsync2 --hipri=1 1>/dev/null 2>&1"):
        print("FAIL ： Fio does not support polling" )
        exit(1)
    time.sleep(3)
    for t in ["randread","randwrite","rw"]:
        cmd="fio --bs=4k --rw=%s --norandommap --name=reads \
                    --filename=%s --size=%s --direct=1 \
                    --ioengine=pvsync2 --hipri=1" %(t,"/dev/%s" % disk,"1G")
        linux.run(cmd)

def run_test():
    disk=get_nvme_disk()
    if not disk:
        print("FAIL the disk was %s" % disk)
        exit(1)

    ret,status = linux.run(" cat /sys/block/%s/queue/io_poll" % disk,True,True)
    print("the ret is %s, status is %s" % (ret,status))
    if not int(status):
        print("FAIL : Could not enable the IO_poll in kernel, please add 'nvme.poll_queues=N'(N>=1) to kernel")
        exit(1)
    for t in [-1,0,1,2,"test" ]:
        ret=linux.run("echo %s > /sys/block/%s/queue/io_poll_delay" % (t,disk))
        if not ret:
            print("run the io_poll on the disk %s and type was %s" % (disk,t))
            linux.run("cat  /sys/block/%s/queue/io_poll_delay" % disk)
            fio_io_poll(disk)
        else:
            print("FAIL : echo %s to %s " % (t,disk))
    return True

if __name__ == '__main__':
    run_test()
