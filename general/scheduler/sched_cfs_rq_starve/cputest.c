#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <errno.h>
#include <unistd.h>

const unsigned long LOOP_COUNT = 1000000000UL;
const unsigned long NS_PER_SEC = 1000000000UL;
static int my_id = 0;
static int secs_slack = 10;

static unsigned long long gettime() {
	struct timespec last;
	if (clock_gettime(CLOCK_MONOTONIC, &last)) {
		fprintf(stderr, "%d: error getting initial time: &d \n", my_id, errno);
	}
	return last.tv_sec * NS_PER_SEC + last.tv_nsec;
}

int main (int argc, char ** argv) {

	unsigned long long last;
	unsigned long long cur;

	if (argc > 1) {
		my_id = atoi(argv[1]);
	}
	if (argc > 2) {
		secs_slack = atoi(argv[2]);
	}

	sleep(10);
	printf("Starting job number %d with %d seconds slack\n", my_id, secs_slack);
	fflush(stdout);

	last = gettime();

	while (1) {
		int i;
		unsigned long long diff;
		for (i = 0; i < LOOP_COUNT; i++ ) {
			;
		}
		cur = gettime();
		diff = cur - last;
		if (diff > (secs_slack * NS_PER_SEC)) {
			printf("%d: has not run in %llu us\n", my_id, (diff) / 1000);
		}
		//printf("%d: loop took %llu ns\n", my_id, diff);

		last = cur;

	}

}

