#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

#define errExit(msg) do { perror(msg); exit(EXIT_FAILURE); } while (0)

int read_proc_state(pid_t pid, char *state)
{
	char proc_path[128];
	FILE *fp;

	snprintf(proc_path, sizeof(proc_path), "/proc/%i/stat", pid);
	fp = fopen(proc_path, "r");
	if (fp == NULL) {
		return -1;
	}

	int ret = fscanf(fp, "%*[^)]%*c %c", state);
	fclose(fp);

	return (ret == 1) ? 0 : -1;
}

/*
 * Waits for process state change.
 *
 * The state is one of the following:
 *
 * R - running
 * S - sleeping
 * D - disk sleep
 * T - stopped
 * t - tracing stopped
 * Z - zombie
 * X - dead
 */
int process_state_wait(pid_t pid, const char state, unsigned int msec_timeout)
{
	char cur_state;
	unsigned int msecs = 0;

	for (;;) {
		if (read_proc_state(pid, &cur_state) == -1) {
			errExit("read_proc_state");
		}

		if (state == cur_state)
			return 0;

		usleep(1000);
		msecs += 1;

		if (msec_timeout && msecs >= msec_timeout) {
			errno = ETIMEDOUT;
			return -1;
		}
	}
}

int main(int argc, char *argv[]) {
	if (argc != 3) {
		fprintf(stderr, "Usage: %s <pid> <state>\n", argv[0]);
		exit(EXIT_FAILURE);
	}

	pid_t pid = atoi(argv[1]);
	char state = argv[2][0];
	unsigned int msec_timeout = 10000;  // timeout of 10 seconds

	if (process_state_wait(pid, state, msec_timeout) == -1) {
		if (errno == ETIMEDOUT) {
			printf("Timeout reached while waiting for process %d to reach state %c\n", pid, state);
		} else {
			errExit("tst_process_state_wait");
		}
		exit(EXIT_FAILURE);
	} else {
		printf("Process %d reached state %c\n", pid, state);
	}

	return 0;
}
