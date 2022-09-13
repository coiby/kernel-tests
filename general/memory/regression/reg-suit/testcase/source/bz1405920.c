#include <stdio.h>
#include <fcntl.h>

main(int argc, char **argv)
{
    int fd;
    char useless;

    fd = open("/proc/sys/vm/percpu_pagelist_fraction", O_RDWR);
    write(fd, &useless, 0);
}
