#!/usr/bin/env python

import sys
import os
import zmq
import fire

def get_zmq_port():
    zmq_port=os.getenv("ZMQ_PORT")
    if None == zmq_port:
        zmq_port = 5678
    else:
        zmq_port = int(zmq_port)
    return zmq_port

def get_msg():
    zmq_port=get_zmq_port()
    context = zmq.Context()
    sock = context.socket(zmq.REQ)
    sock.connect(f"tcp://127.0.0.1:{zmq_port}")
    data = None
    try:
        sock.send_string("get-cmd")
        data = sock.recv_string()
        sock.close()
    except BrokenPipeError as e:
        print("**********************")
        print(e)
        print("**********************")
        print("BrokenPipe")
        print("**********************")
    return data

if __name__ == "__main__":
    fire.Fire(get_msg)
