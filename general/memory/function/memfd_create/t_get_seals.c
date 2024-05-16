#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#ifndef F_SEAL_SEAL
# define F_SEAL_SEAL     0x0001  /* prevent further seals from being set */
#endif
#ifndef F_SEAL_SHRINK
# define F_SEAL_SHRINK   0x0002  /* prevent file from shrinking */
#endif
#ifndef F_SEAL_GROW
# define F_SEAL_GROW     0x0004  /* prevent file from growing */
#endif
#ifndef F_SEAL_WRITE
# define F_SEAL_WRITE    0x0008  /* prevent writes */
#endif
#ifndef F_ADD_SEALS
# define F_ADD_SEALS     (1033)
#endif
#ifndef F_GET_SEALS
# define F_GET_SEALS     (1034)
#endif

#define errExit(msg)    do { perror(msg); exit(EXIT_FAILURE); \
} while (0)

int main(int argc, char *argv[])
{
    int fd;
    unsigned int seals;

    if (argc != 2) {
        fprintf(stderr, "%s /proc/PID/fd/FD\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    fd = open(argv[1], O_RDWR);
    if (fd == -1)
        errExit("open");

    seals = fcntl(fd, F_GET_SEALS);
    if (seals == -1)
        errExit("fcntl");

    printf("Existing seals:");
    if (seals & F_SEAL_SEAL)
        printf(" SEAL");
    if (seals & F_SEAL_GROW)
        printf(" GROW");
    if (seals & F_SEAL_WRITE)
        printf(" WRITE");
    if (seals & F_SEAL_SHRINK)
        printf(" SHRINK");
    printf("\n");

    /* Code to map the file and access the contents of the
       resulting mapping omitted */

    exit(EXIT_SUCCESS);
}

