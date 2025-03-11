### common 6.12.0-0.el10 ########################################################
from flags import *

def setup(exc):
    PID_T = 'unistd.h'
    SIZE_T = 'stddef.h'
    SA_FAMILY_T = "sys/socket.h"
    SOCKADDR = 'sys/socket.h'

    exc['ynl/ynl-priv.h'] = (['string.h', 'linux/netlink.h'],
                                   OK, 'memset memcpy strcpy strlen nlattr NLMSG_HDRLEN')
