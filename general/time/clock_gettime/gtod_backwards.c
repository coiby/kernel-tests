#include <errno.h>
#include <error.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include <sys/time.h>
#include <sys/timex.h>
#include <sys/unistd.h>

/* This test reads gettimeofday rapidly and compares the results.  If
   gettimeofday returns decreasing values, ie) time went backwards, then
   return an error.
 */

#define tv_lt(s,t) \
 (s.tv_sec < t.tv_sec || (s.tv_sec == t.tv_sec && s.tv_nsec < t.tv_nsec))

void print_error(struct timespec tv_start, struct timespec tv_end)
{
	long long time;
	struct timespec tv_diff;

	printf("start time = %10ld.%09ld \n", tv_start.tv_sec, tv_start.tv_nsec);
	printf("end   time = %10ld.%09ld \n", tv_end.tv_sec, tv_end.tv_nsec);

	if(tv_start.tv_nsec > tv_end.tv_nsec){
			tv_end.tv_sec--;
			tv_end.tv_nsec +=1000000000L;
	}

	tv_diff.tv_sec = tv_end.tv_sec - tv_start.tv_sec;
	tv_diff.tv_nsec = tv_end.tv_nsec - tv_start.tv_nsec;
	time = (long long)tv_diff.tv_sec * 1000000000L +
	       (long long)tv_diff.tv_nsec;
	printf("Failed: time went backwards %lld nsec (%ld.%06ld )\n", time,
	       tv_diff.tv_sec, tv_diff.tv_nsec);
}

int main(int argc, char * argv[])
{
	int j;
	struct timespec now, tv_start, tv_end;

	if (argc > 1) {
		return 1;
	}

	clock_gettime(CLOCK_MONOTONIC, &now);
	printf("Test start time = %10ld.%06ds\n", (long int)now.tv_sec,
	       (int)now.tv_nsec);

	for (j = 0; j < 100000; j++) {
		clock_gettime(CLOCK_MONOTONIC, &tv_start);
		clock_gettime(CLOCK_MONOTONIC, &tv_end);

		if(tv_lt(tv_end,tv_start)){
			print_error(tv_start,tv_end);
			return 1;
		}

		tv_start = tv_end;
	}

	clock_gettime(CLOCK_MONOTONIC, &now);
	printf("Test   end time = %10ld.%06ds\n", (long int)now.tv_sec,
	       (int)now.tv_nsec);

	return 0;
}
