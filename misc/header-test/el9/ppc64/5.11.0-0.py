### ppc64(le) 5.11.0-0.el9 #####################################################
from flags import *

def setup(exc):
    PID_T = 'unistd.h'
    SIZE_T = 'stddef.h'
    SA_FAMILY_T = "sys/socket.h"
    SOCKADDR = 'sys/socket.h'

    # https://bugzilla.redhat.com/1908140
    exc['linux/bpf_perf_event.h'] = ([], WARN | BLACKLIST,
                                     'struct pt_regs is undefined in userspace kernel headers')

