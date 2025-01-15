#define _GNU_SOURCE
#include <sys/syscall.h>
#include <linux/sched.h>
#include <linux/sched/types.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

#define SLICE 100000000
#define MIN_SLICE 100000
#define MAX_SLICE 100000000

int main(int argc, char **argv)
{
	pid_t pid;
	int ret;
	unsigned long slice = SLICE;
	pid = getpid();

	if (argc > 1) {
		slice = strtoul(argv[1], NULL, 10);
	}
	if (argc > 2) {
		pid = strtoul(argv[2], NULL, 10);
	}

	printf("setting %d slice to %lu ns\n", pid, slice);
	struct sched_attr a = {
		.size = sizeof(struct sched_attr),
		.sched_policy = 0,
		.sched_runtime = slice
	};
	ret = syscall(SYS_sched_setattr, pid, &a, 0);
	if (ret != 0) {
		perror("sched_setattr()");
		return -1;
	}

	ret = syscall(SYS_sched_getattr, pid, &a, sizeof(struct sched_attr), 0);
	if (ret != 0) {
		perror("sched_getattr()");
		return -1;
	}
	if (slice >= MIN_SLICE && slice <= MAX_SLICE &&
		a.sched_runtime != slice) {
		printf("FAIL -1\n");
		ret = -1;
	} else if (slice < MIN_SLICE && a.sched_runtime != MIN_SLICE ||
			slice > MAX_SLICE && a.sched_runtime != MAX_SLICE ||
				a.sched_policy != 0) {
		printf("FAIL -2\n");
		ret = -2;
	} else {
		printf("PASS\n");
		ret = 0;
	}

	return ret;
}
