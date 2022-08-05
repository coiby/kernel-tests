/* Sleep for 0.5 seconds and verify elapsed time is actually 0.5 seconds.
 * A bug in gettimeofday() on 64-bit ARM returned incorrect values:
 *     https://bugzilla.redhat.com/show_bug.cgi?id=1479588
 *     https://bugzilla.redhat.com/show_bug.cgi?id=1451467
 *
 *     Jeff Bastian <jbastian@redhat.com>
 */

#include <stdio.h>
#include <time.h>

int main(void)
{
    int ret;
    clockid_t clk_id = CLOCK_MONOTONIC_RAW;
    struct timespec tp1, tp2, elapsed;
    struct timespec req, rem;

    ret = clock_gettime(clk_id, &tp1);
    if (ret) {
        perror("ERROR: clock_gettime:");
    }
    printf("1: clock_gettime: tv_sec = %ld, tv_nsec = %lld\n",
           tp1.tv_sec, tp1.tv_nsec);

    printf("Sleeping 0.5 seconds\n");
    req.tv_sec = 0;
    req.tv_nsec = 500000000;
    ret = nanosleep(&req, &rem);
    if (ret) {
        perror("ERROR: nanosleep:");
        printf("       Remaining sleep: tv_sec = %ld, tv_nsec = %lld\n",
               rem.tv_sec, rem.tv_nsec);
    }

    ret = clock_gettime(clk_id, &tp2);
    if (ret) {
        perror("ERROR: clock_gettime:");
    }
    printf("2: clock_gettime: tv_sec = %ld, tv_nsec = %lld\n",
           tp2.tv_sec, tp2.tv_nsec);

    if ((tp2.tv_nsec - tp1.tv_nsec) < 0) {
        elapsed.tv_sec = tp2.tv_sec - tp1.tv_sec - 1;
        elapsed.tv_nsec = 1000000000 + tp2.tv_nsec - tp1.tv_nsec;
    } else {
        elapsed.tv_sec = tp2.tv_sec - tp1.tv_sec;
        elapsed.tv_nsec = tp2.tv_nsec - tp1.tv_nsec;
    }

    printf("Elapsed: %ld.%lld\n", elapsed.tv_sec, elapsed.tv_nsec);

    if (elapsed.tv_sec != 0 ||
        elapsed.tv_nsec < 490000000 ||
        elapsed.tv_nsec > 510000000) {
        printf("FAIL: elapsed time is not approximately 0.5 seconds\n");
        return -1;
    }

    printf("PASS\n");
    return 0;
}
