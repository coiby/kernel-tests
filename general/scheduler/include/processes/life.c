#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/* Return diff in us. left should be after right */
static long time_sub(struct timespec *left, struct timespec *right)
{
    return (left->tv_sec - right->tv_sec) * 1000 * 1000 + (left->tv_nsec - right->tv_nsec) / 1000;
}

static void running(unsigned long us)
{
    struct timespec ts_start, ts_current;

    clock_gettime(CLOCK_MONOTONIC, &ts_start);
    while (1) {
        long elapsed_us;

        clock_gettime(CLOCK_MONOTONIC, &ts_current);
        elapsed_us = time_sub(&ts_current, &ts_start);
        if (elapsed_us >= us)
            break;
    }
}

static void sleeping(unsigned long us)
{
    struct timespec ts;

    ts.tv_sec = 0;
    ts.tv_nsec = us * 1000;
    nanosleep(&ts, NULL);
}

int main(int argc, char *argv[])
{
    unsigned long sleep_us, run_us;

    if (argc < 3) {
        printf("too few arguments\n");
        return -1;
    }
    printf("Just like life ...\nYou work, You sleep.\n");

    run_us = atoi(argv[1]);
    sleep_us = atoi(argv[2]);

    while (1) {
        if (run_us)
            running(run_us);

        if (sleep_us)
            sleeping(sleep_us);
    }

    return 0;
}

