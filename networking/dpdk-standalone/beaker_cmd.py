#!/usr/bin/env python3

import os
import sys
import time
from bash import bash
from functools import wraps
import contextlib
import zmq

zmq_port=os.getenv("ZMQ_PORT")
if None == zmq_port:
    zmq_port = 5678
else:
    zmq_port = int(zmq_port)

def singleton(cls, *args, **kw):
    instances = {}
    def _singleton():
       if cls not in instances:
            instances[cls] = cls(*args, **kw)
       return instances[cls]
    return _singleton

@singleton
class My_socket():
    def __init__(self):
        address = f"tcp://127.0.0.1:{zmq_port}"
        context = zmq.Context().instance()
        sock = context.socket(zmq.REP)
        sock.bind(address)
        self.sock =  sock
        pass

    def get_socket(self):
        return self.sock

def set_check(ret):
    def my_wrap(f):
        @wraps(f)
        def log_f_as_called(*args, **kwargs):
            my_command = f'{f.__name__} {args} {kwargs}'
            cmd = f"""[  BEGIN   ] :: Running '{my_command}' """
            log(cmd)
            value = f(*args, **kwargs)
            cmd = f"""[ END ] [   {value}   ] :: Running '{my_command}' """
            log(cmd)
            return value
        return log_f_as_called
    return my_wrap

def basic_send_command(cmd):
    my_cmd = cmd + os.linesep
    sock = My_socket().get_socket()
    try:
        sock.recv_string()
        sock.send_string(my_cmd)
    except BrokenPipeError as e:
        print("**********************")
        print(e)
        print("**********************")
        print("BrokenPipe\n")
        print("**********************")

def send_command(cmd):
    basic_send_command(cmd)
    basic_send_command(os.linesep)
    pass


def log(str_log):
    if isinstance(str_log,str):
        str_log = str_log.replace('"','\\"')
    cmd = f""" rlLog "{str_log}" """
    send_command(cmd)

def run(cmd, str_ret_val="0"):
    my_cmds = cmd + os.linesep
    my_cmds = [ i.strip() for i in my_cmds.split(os.linesep) ]
    for i in my_cmds:
        if len(i) > 0:
            i = i.replace('"','\\"')
            real_cmd = """ rlRun  "{}" "{}" """.format(i, str_ret_val)
            send_command(real_cmd)
    pass

def log_and_run(cmd, str_ret_val="0"):
    log(cmd)
    run(cmd, str_ret_val)
    pass

def rl_fail(cmd):
    cmd = cmd + os.linesep
    real_cmd = """ rlFail  "{}" """.format(cmd)
    send_command(real_cmd)
    pass

def rl_pass(cmd):
    cmd = cmd + os.linesep
    real_cmd = """ rlPass  "{}" """.format(cmd)
    send_command(real_cmd)
    pass

def shpushd(path):
    cmd = f"""rlRun "pushd {path}" """
    send_command(cmd)
    pass

def shpopd():
    cmd = "rlRun popd"
    send_command(cmd)
    pass

@contextlib.contextmanager
def pushd(path):
    shpushd(path)
    try:
        yield
    finally:
        shpopd()


@contextlib.contextmanager
def enter_phase(str):
    cmd = f""" rlPhaseStartTest '{str}' """
    send_command(cmd)
    time.sleep(1)
    try:
        yield
    finally:
        send_command("rlPhaseEnd")
        time.sleep(1)


def val_check_equal(a, b, str_comm=""):
    ret = 0 if a == b else 1
    if ret == 1:
        cmd = f""" rlFail  "{str_comm}" """
    else:
        cmd = f""" rlPass  "{str_comm}" """
    send_command(cmd)
    pass


def val_check_not_equal(a, b, str_comm=""):
    ret = 1 if a == b else 0
    if ret == 1:
        cmd = f""" rlFail  "{str_comm}" """
    else:
        cmd = f""" rlPass  "{str_comm}" """
    send_command(cmd)

#Must do not remove log line
def sync_set(target,value,timeout=86400):
    log(f"Start sync_set {value}")
    send_command(f"sync_set {target} {value} {timeout}")
    log(f"End sync_set {value}")

#Must do not remove log line
def sync_wait(target,value,timeout=86400):
    log(f"Start sync_wait {value}")
    send_command(f"sync_wait {target} {value} {timeout}")
    log(f"End sync_wait {value}")
