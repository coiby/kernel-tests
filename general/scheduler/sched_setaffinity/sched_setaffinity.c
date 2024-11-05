#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <string.h>
#include <sys/syscall.h>
#include <errno.h>

int test_result;
#define PASS 0
#define FAIL_RET 2
#define FAIL_ERR 4
#define FAIL_MASK 8

static int expect_retval;
static int expect_errno;
static int retval;
static char affinity_status[256];

/*
 * Convert '1-9,10' to bit mask
 */
void parse_cpu_list(const char *cpu_affinity, cpu_set_t *cpus)
{
	CPU_ZERO(cpus);
	char *token;
	char *str = strdup(cpu_affinity);
	char *ptr = str;

	if (atoi(cpu_affinity) < 0) {
		CPU_ZERO(cpus);
		return;
	}

	while ((token = strsep(&ptr, ",")) != NULL) {
		char *range_start = token;
		char *range_end = NULL;

		if (strchr(token, '-')) {
			range_start = strtok(token, "-");
			range_end = strtok(NULL, "-");
		}

		if (range_end) {
			int start = atoi(range_start);
			int end = atoi(range_end);
			for (int i = start; i <= end; i++) {
				CPU_SET(i, cpus);
			}
		} else {
			int cpu = atoi(range_start);
			CPU_SET(cpu, cpus);
		}
	}

	free(str);
}

/*
 * get cpu affinity from the /proc/[pid]/status file
 */
void get_affinity_status(pid_t pid, char *affinity)
{
	char path[256];
	sprintf(path, "/proc/%d/status", pid);

	FILE *file = fopen(path, "r");
	if (!file) {
		perror("fopen");
		return;
	}

	char line[256];
	while (fgets(line, sizeof(line), file)) {
		if (strstr(line, "Cpus_allowed_list") != NULL) {
			break;
		}
	}

	char *start = line + strlen("Cpus_allowed_list: ");
	char *end = strrchr(start, ' ');
	if (end == NULL) {
		end = start + strlen(start);
	}

	size_t length = end - start;
	strncpy(affinity, start, length);
	end = strrchr(affinity, '\n');
	if (end) {
		*end = '\0';
		length = strlen(affinity);
	}
	affinity[length] = '\0';

	fclose(file);
}

void check_errno_retval(int exp_errno, int exp_retval)
{
	if (errno != expect_errno) {
		test_result += FAIL_ERR;
		fprintf(stderr, "FAIL: errno: expect %d got %d\n", exp_errno, errno);
	}
	if (retval != expect_retval) {
		test_result += FAIL_RET;
		fprintf(stderr, "FAIL: retval: expect %d got %d\n", exp_retval, retval);
	}

	if (test_result == PASS)
		printf("PASS: errno=%d, retval=%d\n", exp_errno, exp_retval);

}

void check_status_cpumask(char *expect_mask)
{
	if (strcmp(expect_mask, affinity_status)) {
		test_result += FAIL_MASK;
		fprintf(stderr, "FAIL: cpumask: expect %s got %s\n", expect_mask,
				affinity_status);
	} else {
		printf("PASS: cpu_mask=%s\n", affinity_status);
	}
}

int main(int argc, char *argv[])
{
	cpu_set_t set;
	cpu_set_t input_set;
	long lret;
	pid_t pid;
	int ret;
	char old_status[256];

	if (argc != 5) {
		fprintf(stderr, "Usage: %s <cpu-list> <expect errno> \
				<expect return value> <expect mask in status>\n",
				argv[0]);
		exit(EXIT_FAILURE);
	}

	CPU_ZERO(&set);
	CPU_ZERO(&input_set);

	parse_cpu_list(argv[1], &input_set);
	expect_retval = atoi(argv[2]);
	expect_errno = atoi(argv[3]);

	get_affinity_status(getpid(), old_status);

	retval = sched_setaffinity(0, sizeof(input_set), &input_set);
	check_errno_retval(expect_errno, expect_retval);
	get_affinity_status(getpid(), affinity_status);
	check_status_cpumask(argv[4]);

	return test_result;
}
