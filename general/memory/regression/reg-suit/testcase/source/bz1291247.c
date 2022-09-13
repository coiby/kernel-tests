#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <assert.h>
#include <sys/wait.h>


#define SIZE (1024)
#define PROT (PROT_READ | PROT_WRITE)
#define PFLAGS (MAP_PRIVATE)
#define SFLAGS (MAP_SHARED)

#define FILENAME "./huge_test/bz1291247.txt"


int main(int argc, char* argv[])
{
    int fd = 0, result = 0;
    void *paddr = NULL, *saddr=NULL;


    fd = open(FILENAME, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
    assert(fd > 0);

    paddr = mmap(NULL,  SIZE, PROT, PFLAGS, fd, 0);
    saddr = mmap(NULL,  SIZE, PROT, SFLAGS, fd, 0);

    printf("paddr=0x%08x, saddr=0x%08x, fd=%d\n", paddr, saddr, fd);
    assert((paddr != MAP_FAILED) && (saddr != MAP_FAILED));

    memset(paddr, 0, SIZE);
    memset(saddr, 0, SIZE);
    if (fork() == 0)
    {
        sleep(3);
    }
    else
    {
        /* trigger bz1291247 */
        memset(paddr, 1, SIZE);
        memset(saddr, 1, SIZE);

        wait(NULL);
        close(fd);
    }

    return 0;
}

