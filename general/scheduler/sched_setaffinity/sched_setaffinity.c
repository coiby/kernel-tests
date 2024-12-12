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

static int expect_retval; // Expected return value from sched_setaffinity
static int expect_errno;  // Expected errno value after sched_setaffinity
static int retval;		  // Return value from sched_setaffinity
static char affinity_status[256]; // Current CPU affinity status as a string

/*
 * Convert CPU list in the form of ranges and individual CPUs to bit mask
 * This function parses a CPU list in the format '1-3,5,7' and sets the
 * appropriate CPUs in the cpu_set_t (cpus) bitmask.
 */
void parse_cpu_list(const char *cpu_affinity, cpu_set_t *cpus)
{
	CPU_ZERO(cpus); // Initialize the cpu_set_t to empty (no CPUs selected)
	char *token;
	char *str = strdup(cpu_affinity); // Duplicate the CPU list string to tokenize
	char *ptr = str;

	// For a negative cpu_affinity, return an empty cpu_set_t bitmask
	if (atoi(cpu_affinity) < 0) {
		CPU_ZERO(cpus);
		return;
	}

	// Loop through the tokens (split by commas) and parse ranges or individual CPUs
	while ((token = strsep(&ptr, ",")) != NULL) {
		char *range_start = token;
		char *range_end = NULL;

		// If token contains a range (e.g., '1-3'), split it into start and end
		if (strchr(token, '-')) {
			range_start = strtok(token, "-");
			range_end = strtok(NULL, "-");
		}

		// If it's a range, iterate over the CPUs in the range and set them in the mask
		if (range_end) {
			int start = atoi(range_start);
			int end = atoi(range_end);
			for (int i = start; i <= end; i++) {
				CPU_SET(i, cpus); // Add each CPU to the cpu_set_t
			}
		} else {
			// If it's a single CPU, add it to the cpu_set_t
			int cpu = atoi(range_start);
			CPU_SET(cpu, cpus);
		}
	}

	// Clean up the duplicated string
	free(str);
}

/*
 * Get CPU affinity from the /proc/[pid]/status file
 * This function retrieves the current CPU affinity of the process by reading
 * the "/proc/[pid]/status" file and looking for the "Cpus_allowed_list" field.
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
	// Search for the "Cpus_allowed_list" line in the status file
	while (fgets(line, sizeof(line), file)) {
		if (strstr(line, "Cpus_allowed_list") != NULL) {
			break;
		}
	}

	// Extract the CPU affinity list from the file
	char *start = line + strlen("Cpus_allowed_list: ");
	char *end = strrchr(start, ' ');
	if (end == NULL) {
		end = start + strlen(start);
	}

	// Copy the affinity list to the provided buffer
	size_t length = end - start;
	strncpy(affinity, start, length);
	end = strrchr(affinity, '\n');
	if (end) {
		*end = '\0'; // Remove the trailing newline
		length = strlen(affinity);
	}
	affinity[length] = '\0'; // Null-terminate the string

	fclose(file);
}

/*
 * Check whether the actual return value and errno match the expected values
 * This function compares the actual and expected return value and errno.
 * If they don't match, it adds a failure code to the test_result and logs an
 * error message.
 */
void check_errno_retval(int exp_errno, int exp_retval)
{
	if (errno != exp_errno) {
		test_result += FAIL_ERR;
		fprintf(stderr, "FAIL: errno: expect %d got %d\n", exp_errno, errno);
	}
	if (retval != exp_retval) {
		test_result += FAIL_RET;
		fprintf(stderr, "FAIL: retval: expect %d got %d\n", exp_retval, retval);
	}

	// If both errno and retval match expectations, print success
	if (test_result == PASS)
		printf("PASS: errno=%d, retval=%d\n", exp_errno, exp_retval);
}

/*
 * Compare the expected CPU mask with the current affinity status
 * This function compares the CPU mask provided by the user with the one
 * retrieved from the process's status file. If they don't match, it adds a
 * failure code to the test_result and logs an error message.
 */
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

/*
 * Main function to perform CPU affinity test
 * This function parses the command-line arguments, sets the CPU affinity using
 * sched_setaffinity, and checks the results against the expected values.
 */
int main(int argc, char *argv[])
{
	cpu_set_t set;
	cpu_set_t input_set;
	pid_t pid;
	char old_status[256];

	// Ensure correct number of arguments
	if (argc != 5) {
		fprintf(stderr, "Usage: %s <cpu-list> <expect errno> \
				<expect return value> <expect mask in status>\n",
				argv[0]);
		exit(EXIT_FAILURE);
	}

	CPU_ZERO(&input_set); // Initialize the cpu_set_t for the input CPU list

	// Parse the input CPU list (e.g., "1-3,5,7") and fill the input_set with appropriate CPUs
	parse_cpu_list(argv[1], &input_set);

	// Convert the expected return value and errno from command-line arguments
	expect_retval = atoi(argv[2]);
	expect_errno = atoi(argv[3]);

	// Retrieve the current CPU affinity status
	get_affinity_status(getpid(), old_status);

	// Set the CPU affinity using sched_setaffinity and store the return value
	retval = sched_setaffinity(0, sizeof(input_set), &input_set);

	// Check if the return value and errno match the expected values
	check_errno_retval(expect_errno, expect_retval);

	// Retrieve the updated CPU affinity status
	get_affinity_status(getpid(), affinity_status);

	// Compare the current CPU mask with the expected one
	check_status_cpumask(argv[4]);

	// Return the final test result (PASS or failure code)
	return test_result;
}
