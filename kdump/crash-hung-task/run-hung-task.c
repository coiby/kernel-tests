/*
 * This test program tests the behavior of hung task handling.
 */
#define	_GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <stdio.h>
#include <limits.h>
#include <locale.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>
#include <pthread.h>
#include <math.h>
#include <fcntl.h>
#include <sched.h>
#include <linux/futex.h>

#define HUNGTEST	"/debug/hungtest"

static int nchild = 20;
pid_t pids[20];

/*
 * This task context-switch one and then call FUTEX_WAIT to sleep.
 */
static void hung_child(void)
{

	int i, fd;
	char buf[4];

	usleep(1);

	if ((fd = open(HUNGTEST, O_RDONLY)) < 0) {
		fprintf(stderr, "Error: Can't open " HUNGTEST "!\n");
		exit(1);
	}
	read(fd, buf, sizeof(buf));
}

int main(int argc, char *argv[])
{
	int i;
	int status;

	for (i = 0; i < nchild; i++) {
		if (!fork()) {
			hung_child();
			exit(1);
		}
	}

	for (i = 0; i < nchild; i++)
		waitpid(pids[i], &status, 0);
}
