#define _GNU_SOURCE

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <sched.h>
#include <pthread.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#define CONSTANT_STRING "AAAAAAAAAAAAAAAAAAAAAAAAA"

int setaffin;

static void *busy(void *arg)
{
    int            thrnum = *(int *)arg;
    cpu_set_t      cps;
    unsigned int   l = sizeof(cps);

    if (setaffin) {
        CPU_ZERO(&cps);
        CPU_SET(thrnum, &cps);
        sched_setaffinity(syscall(SYS_gettid), l, &cps);
    }

    while (1) {
	int tmpfd;
	tmpfd = open("/tmp/test", O_SYNC | O_CREAT | O_RDWR, S_IRUSR | S_IWUSR);
	write(tmpfd, CONSTANT_STRING, sizeof(CONSTANT_STRING));
	write(tmpfd, CONSTANT_STRING, sizeof(CONSTANT_STRING));
	write(tmpfd, CONSTANT_STRING, sizeof(CONSTANT_STRING));
	close(tmpfd);
    }

    return((void *)0);
}

int main(int argc, char **argv)
{
    pthread_t    thr[96];
    time_t       now;
    char         fname[256], line[1024], toss[32];
    FILE         *fp;
    int          i, ret, bthread, tnums[96];
    unsigned long user, sys;

    user = sys = 0;
    if (argc < 2) {
        fprintf(stderr, "How many busy threads? [1-96]\n");
        exit(1);
    }

    bthread = atoi(argv[1]);
    if (bthread < 1 || bthread > 96) {
        fprintf(stderr, "Busy thread count must be between 1 and 96\n");
        exit(1);
    }

    if (argc > 2)
        setaffin = 1;

    setbuf(stdout, 0);
    for (i = 0; i < bthread; i++) {
        tnums[i] = i;
        ret = pthread_create(&thr[i], 0, busy, (void *)&tnums[i]);
        if (ret) {
            printf("Failed at %d\n", i);
            exit(1);
        }
    }

    sprintf(fname, "/proc/%d/stat", getpid());
    fp = fopen(fname, "r");
    while (1) {
        fgets(line, sizeof(line), fp);
        sscanf(line, "%s %s %s %s %s %s %s %s %s %s %s %s %s %lu %lu",
               toss, toss, toss, toss, toss, toss, toss, toss, toss, toss,
               toss, toss, toss, &user, &sys);
        while (fgets(line, sizeof(line), fp))
            ;
        rewind(fp);
        time(&now);
        printf("Total centiseconds: user %lu sys %lu at %s", user, sys,
               ctime(&now));
        usleep(60000000);
    }
}
