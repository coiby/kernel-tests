#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <stdio.h>
#include <stdlib.h>

#define SHMSZ     2700000

int main(int argc, char* argv[])
{
    char c;
    int shmid;
    key_t key;
    size_t size;
    char *shm, *s;

    if (argc <= 2)
    {
        printf("usage: shmtest <key> <size>\n");
        return 1;
    }
    key = (key_t)atol(argv[1]);
    size= (size_t)atol(argv[2]);
    printf("shmtest, key=%d, size=%lu\n", key, size);

    /*
     * Create the segment.
     */
    if ((shmid = shmget(key, size, IPC_CREAT | 0666)) < 0) {
        perror("shmget");
        return 1;
    }

    /*
     * Now we attach the segment to our data space.
     */
    if ((shm = shmat(shmid, NULL, 0)) == (char *) -1) {
        perror("shmat");
        return 1;
    }

    //sleep(1);

    //if (shmdt(shm) < 0)
    //{
    //    perror("shmdt");
    //    return 1;
    //}


    return 0;
}

