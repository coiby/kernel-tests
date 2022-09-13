#!/usr/bin/env python2.7
from os import mkdir
from threading import Thread
from time import sleep
import os
import subprocess
import sys

__author__ = 'cyberax'

count = 0

'''
chuhu@ updates to use the general/include/libmme.sh for cgroup operations
'''

def threadproc():
    global count
    count += 1
    sleep(0.01)
    count -= 1
    sleep(2)
    exit(0)

def do_threads():
    sleep(2)
    while True:
        while count > 200:
            sleep(0.01)

        th = Thread(target=threadproc)
        th.start()


def do_reader(pid):
    global cgroup_task_1001
    global cgroup_task_delegate
    while True:
        with open(cgroup_task_1001, "r") as fl:
            fl.readlines()
        with open(cgroup_task_delegate, "r") as fl:
            lines = fl.readlines()
        for l in lines:
            try:
                with open("/proc/%s/smaps" % l.strip(), "r") as fl:
                    fl.readlines()
            except:
                pass

def get_output(cmdline):
    if sys.version_info[0] == 2:
        return subprocess.check_output(cmdline, shell=True)
    if sys.version_info[0] == 3:
        return subprocess.check_output(cmdline, encoding='UTF-8', shell=True)

cgroup_version = os.getenv('CGROUP_VERSION')
tasks = os.getenv('CGROUP_TASK_FILE')
cgroup_task_1001 = get_output("cgroup_get_path ck/1001 memory").strip('\n')+'/'+tasks
cgroup_task_delegate = get_output("cgroup_get_path ck/1001/delegate memory").strip('\n')+'/'+tasks
print (tasks,cgroup_version,cgroup_task_1001, cgroup_task_delegate)

pid = os.fork()
if pid == 0:
    do_threads()
    exit(0)

try:
    cmd = "cgroup_create ck/1001/delegate memory"
    output = get_output(cmd)
    print(output)
except:
    pass

with open(cgroup_task_delegate, 'w') as fl:
    fl.write('%d\n' % pid)

do_reader(pid)
