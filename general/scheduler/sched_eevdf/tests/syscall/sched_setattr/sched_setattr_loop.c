#define _GNU_SOURCE
#include <sys/syscall.h>
#include <linux/sched.h>
#include <linux/sched/types.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define MIN_SLICE 100000
#define MAX_SLICE 100000000
#define LOOP 1
#define STEP 10000000 //10 ms

unsigned long start_time;
static unsigned long duration = 120; //default 120s
static pid_t pid;

int test_continue()
{
	struct timespec now;
	int ret = clock_gettime(CLOCK_REALTIME, &now);
	if (ret < 0) {
		perror("clock_gettime()");
		exit(1);
	}
	if (now.tv_sec > start_time + duration)
		return 0;
	return 1;
}

int main(int argc, char **argv)
{
	int ret;
	unsigned long slice;
	int i, loop = LOOP;

	/* by default current running process */
	pid = getpid();
	if (argc > 1) {
		pid = strtoul(argv[1], NULL, 10);
	}
	if (argc >= 2) {
		duration = strtoul(argv[2], NULL, 10);
	}

	struct sched_attr a = {
		.size = sizeof(struct sched_attr),
		.sched_policy = 0,
		.sched_runtime = slice
	};
	struct timespec start;
	ret = clock_gettime(CLOCK_REALTIME, &start);
	if (ret < 0) {
		perror("clock_gettime()");
		exit(1);
	}
	start_time = start.tv_sec;
	while (test_continue()) {
		for (slice = MIN_SLICE; slice <= MAX_SLICE; slice += STEP) {
			a.sched_runtime = slice;
			ret = syscall(SYS_sched_setattr, pid, &a, 0);
			if (ret != 0) {
				perror("sched_setattr()");
				return -1;
			}
		}
	}

	return 0;
}
