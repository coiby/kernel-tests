/*
 * Run several "chains" of processes in parallel
 *
 * A process fork only once after a short wait, then wait for some more time
 * and exits. The waiting periods are such as the number of live processes in
 * a chain stays more or less constant (CHAIN_LEN).
 *
 * To kill all the processes at the end of the test:
 * $ while killall -9 fork_snake; do echo killing; done
 */

#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>

/* Number of parrallel processes */
#define PROCESSES 10

/* Wait time between forks in us */
#define WAIT_TIME 10000
/* The approximate length of the chains */
#define CHAIN_LEN 10

int main(int argc, char *argv[])
{
	int i, count = 0, pos, fd;
	pid_t pid;

	for (i = 0; i < PROCESSES; i++) {
		pid = fork();
		if (pid == -1) {
			/* error */
			perror("parent fork");
			return 1;
		}
		if (!pid) {
			pos = i;
			break;
		}
	}

	while (1) {
		count++;
		/*
		if (!pos && !(count%1000))
			printf("count: %i\n", count);
		*/
		fd = open("./CLEANUP_FLAG", O_RDONLY);
		if (fd >= 0)
			return 1;

		pid = fork();
		if (pid == -1) {
			/* error */
			perror("fork");
			return 1;
		}
		if (pid) {
			/* parent */
			usleep((CHAIN_LEN - 1) * WAIT_TIME);
			break;
		} else {
			/* child */
			usleep(WAIT_TIME);
		}

	}

	return 0;
}
