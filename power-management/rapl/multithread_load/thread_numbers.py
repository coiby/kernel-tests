#!/usr/bin/python

import sys

if len(sys.argv) < 2:
        x=1
else:
        x=int(sys.argv[1])

def threads_num(t):
        cores=[]
        if t<=8:
                cores=range(t)
        else:
                cores.append(0)
                for a in range(8-2):
                        cores.append(int(round( 1+a*(t-2)/(8-2.0) )))
                cores.append(t-1)
        return cores

for i in threads_num(x):
        print i
