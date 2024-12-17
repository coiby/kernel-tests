#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/sched.h>
#include <linux/sched/types.h>
#include <time.h>
#include <string.h>

static volatile int overrun_count = 0;
static unsigned long duration = 5; // test run for 5 seconds
static unsigned long start_sec; // record test start time
static int ret; // return value

static void sigxcpu_handler(int signo)
{
	if (signo == SIGXCPU)
		overrun_count++;
}

static int test_continue(void)
{
	struct timespec now;
	unsigned long elapsed_time;

	if (clock_gettime(CLOCK_MONOTONIC, &now) == -1) {
		perror("clock_gettime start");
		exit(1);
	}
	if (now.tv_sec - start_sec > duration)
		return 0;
	return 1;
}

int main(int argc, char *argv[])
{
	struct sched_attr attr = {};
	pid_t pid = getpid();
	struct timespec start;
	/* the overrun check flag, 1: enabled, 0: disable */
	int overrun_check;
	/* runtime overrun check enable status string. "enabled" or "not enabled" */
	char check_status[128] = {};
	/* buffer for message of the final test result */
	char result_str[4096] = {};
	/* signal receive status str, "received" or "not received"*/
	char signal_str[32] = {};

	struct sigaction sa = {0};
	sa.sa_handler = sigxcpu_handler;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = SA_RESTART;
	if (sigaction(SIGXCPU, &sa, NULL) < 0) {
		perror("sigaction");
		exit(EXIT_FAILURE);
	}

	if (argc > 1)
		overrun_check = !!atoi(argv[1]);

	if (overrun_check)
		sprintf(check_status, "%s", "enabled");
	else
		sprintf(check_status, "%s", "disabled");

	attr.size = sizeof(attr);
	attr.sched_policy = SCHED_DEADLINE;
	if (overrun_check)
		// enable overrun notifications
		attr.sched_flags = SCHED_FLAG_DL_OVERRUN;
	else
		// disable overrun notifications
		attr.sched_flags = 0;

	/* in each 20 ms period, allow run 10ms */
	attr.sched_runtime = 10 * 1000 * 1000;    // 10 ms
	attr.sched_deadline = 20 * 1000 * 1000;   // 20 ms
	attr.sched_period = 20 * 1000 * 1000;     // 20 ms

	if (syscall(SYS_sched_setattr, pid, &attr, 0) < 0) {
		perror("sched_setattr");
		exit(EXIT_FAILURE);
	}

	printf("Running SCHED_DEADLINE task with overruns notification %s.\n",
			check_status);

	if (clock_gettime(CLOCK_MONOTONIC, &start) == -1) {
		perror("clock_gettime start");
		exit(1);
	}

	start_sec = start.tv_sec;
	// workload that exceeds runtime
	printf("Running workload that exceeds the runtime limitation for %ds.\n",
			duration);
	while (test_continue()) {
		for (volatile int i = 0; i < 100000000; ++i) {
		}
		usleep(1000);
	}

	if (overrun_count > 0 ) {
		if (overrun_check) {
			sprintf(result_str, "PASS: ");
			ret = 0;
		} else {
			sprintf(result_str, "FAIL: ");
			ret = 1;
		}
		sprintf(signal_str, "received");
	} else {
		if (overrun_check) {
			sprintf(result_str, "FAIL: ");
			ret = 1;
		} else {
			sprintf(result_str, "PASS: ");
			ret = 0;
		}
		sprintf(signal_str, "not received");
	}

	sprintf(result_str+strlen(result_str),
			"SIGXCPU %s while overrun notification %s. Overrun count: %d.\n",
			signal_str, check_status, overrun_count);
	printf("%s", result_str);

	return ret;
}
