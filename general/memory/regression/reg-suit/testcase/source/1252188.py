#!/usr/bin/env python2.7
from os import mkdir
from threading import Thread
from time import sleep
import os

__author__ = 'cyberax'

count = 0


def threadproc():
    global count
    count += 1
    sleep(0.01)
    count -= 1


def do_threads():
    sleep(2)
    while True:
        while count > 200:
            sleep(0.01)

        th = Thread(target=threadproc)
        th.start()


def do_reader(pid):
    while True:
        with open("/sys/fs/cgroup/memory/ck/1001/tasks", "r") as fl:
            fl.readlines()
        with open("/sys/fs/cgroup/memory/ck/1001/delegate/tasks", "r") as fl:
            lines = fl.readlines()
        for l in lines:
            try:
                with open("/proc/%s/smaps" % l.strip(), "r") as fl:
                    fl.readlines()
            except:
                pass

pid = os.fork()
if pid == 0:
    do_threads()
    exit(0)

try:
     mkdir('/sys/fs/cgroup/memory/ck')
     mkdir('/sys/fs/cgroup/memory/ck/1001')
     mkdir('/sys/fs/cgroup/memory/ck/1001/delegate')
except:
    pass

with open('/sys/fs/cgroup/memory/ck/1001/delegate/tasks', 'w') as fl:
    fl.write('%d\n' % pid)

do_reader(pid)
