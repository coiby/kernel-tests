/*
 * Testcase for bz1249856/bz1233300/bz1254322
 * Author: Herton R. Krzesinski <herton@redhat.com>
 * Should trigger a crash under kernel-debug on affected versions
 */

#include <stdio.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>

#define NSEM 1
#define NSET 5

int sid[NSET];

void thread()
{
    struct sembuf op;
    int s;
    uid_t pid = getuid();

    s = rand() % NSET;
    op.sem_num = pid % NSEM;
    op.sem_op = 1;
    op.sem_flg = SEM_UNDO;

    semop(sid[s], &op, 1);
    exit(EXIT_SUCCESS);
}

void create_set()
{
    int i, j;
    pid_t p;
    union {
        int val;
        struct semid_ds *buf;
        unsigned short int *array;
        struct seminfo *__buf;
    } un;

    /* Create and initialize semaphore set */
    for (i = 0; i < NSET; i++) {
        sid[i] = semget(IPC_PRIVATE , NSEM, 0644 | IPC_CREAT);
        if (sid[i] < 0) {
            perror("semget");
            exit(EXIT_FAILURE);
        }
    }
    un.val = 0;
    for (i = 0; i < NSET; i++) {
        for (j = 0; j < NSEM; j++) {
            if (semctl(sid[i], j, SETVAL, un) < 0)
                perror("semctl");
        }
    }

    /* Launch threads that operate on semaphore set */
    for (i = 0; i < NSEM * NSET * NSET; i++) {
        p = fork();
        if (p < 0)
            perror("fork");
        if (p == 0)
            thread();
    }

    /* Free semaphore set */
    for (i = 0; i < NSET; i++) {
        if (semctl(sid[i], NSEM, IPC_RMID))
            perror("IPC_RMID");
    }

    /* clear errno, or it will be ECHILD ever since it's set */
    errno = 0;
    /* Wait for forked processes to exit */
    while (wait(NULL)) {
        if (errno == ECHILD)
            break;
    };
}

int main(int argc, char **argv)
{
    pid_t p;

    srand(time(NULL));

    while (1) {
        p = fork();
        if (p < 0) {
            perror("fork");
            exit(EXIT_FAILURE);
        }
        if (p == 0) {
            create_set();
            goto end;
        }

        errno = 0;
        /* Wait for forked processes to exit */
        while (wait(NULL)) {
            if (errno == ECHILD)
                break;
        };
    }
end:
    return 0;
}

