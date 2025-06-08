#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sched.h>
#include <errno.h>

static int count = 0;
static int policy = 0;
static struct sched_param param;

void pstat(void) {
        printf("[starver] count: %d, policy: %d, sched_priority: %d\n",
                count, policy, param.sched_priority);
        fflush(stdout);
}

int main(void) {
        while (1) {
                count++;

                policy = sched_getscheduler(0);
                if (sched_getparam(0, &param) == -1) {
                        perror("sched_getparam");
                }

                if (count % 100 == 0) {
                        pstat();
                }

                usleep(1000);
        }
        return 0;
}
