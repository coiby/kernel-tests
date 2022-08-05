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
 (s.tv_sec < t.tv_sec || (s.tv_sec == t.tv_sec && s.tv_usec < t.tv_usec))

void print_error(struct timeval tv_start, struct timeval tv_end)
{
	long long time;
	struct timeval tv_diff;

	printf("start time = %10ld.%06ld \n", tv_start.tv_sec,
	       tv_start.tv_usec);
	printf("end time = %10ld.%06ld \n", tv_end.tv_sec, tv_end.tv_usec);

	if(tv_start.tv_usec > tv_end.tv_usec){
			tv_end.tv_sec--;
			tv_end.tv_usec +=1000000L;
	}

	tv_diff.tv_sec = tv_end.tv_sec - tv_start.tv_sec;
	tv_diff.tv_usec = tv_end.tv_usec - tv_start.tv_usec;
	time = (long long)tv_diff.tv_sec * 1000000000L +
	       (long long)tv_diff.tv_usec * 1000L;
	printf("Failed: time went backwards %lld nsec (%ld.%06ld )\n", time,
	       tv_diff.tv_sec, tv_diff.tv_usec);
}

int main(int argc, char * argv[])
{
	int j;
	struct timeval now, tv_start, tv_end;

	if (argc > 1) {
		return 1;
	}

	gettimeofday(&now,NULL);
	printf("Test start time = %10ld.%06ds\n", (long int)now.tv_sec,
	       (int)now.tv_usec);

	for (j = 0; j < 10000000; j++) {
		gettimeofday(&tv_start, NULL);
		gettimeofday(&tv_end, NULL);

		if(tv_lt(tv_end,tv_start)){
			print_error(tv_start,tv_end);
			return 1;
		}

		tv_start = tv_end;
	}

	gettimeofday(&now,NULL);
	printf("Test end time = %10ld.%06ds\n", (long int)now.tv_sec,
	       (int)now.tv_usec);

	return 0;
}
