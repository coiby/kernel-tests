/*
 * Determine if the time source used for gettimeofday is stable by
 * checking for large jumps in a short period of time.
 *
 * Author:  Jeff Moyer <jmoyer@redhat.com>
 */
#include <errno.h>
#include <libgen.h>
#include <stdio.h>
#include <sys/time.h>

double elapsed(struct timeval start, struct timeval end)
{
	double t1, t2;
	t1 =  (double)start.tv_sec + (double)start.tv_usec/(1000*1000);
	t2 =  (double)end.tv_sec + (double)end.tv_usec/(1000*1000);
	return t2-t1;
}

int
main(int argc, char **argv)
{
	struct timeval tv1, tv2;
	double timediff;

	if (argc > 1) {
		printf("Usage: %s\n", basename(argv[0]));
		return 1;
	}

	if (gettimeofday(&tv1, NULL) < 0)
		goto out_gtod;
	if (gettimeofday(&tv2, NULL) < 0)
		goto out_gtod;
	timediff = elapsed(tv1, tv2);

	if (timediff >= 1) {
		printf("back-to-back calls of gettimeofday yielded a time "
		       "difference greater than 1 second!\n");
		printf("Difference: %f seconds\n", timediff);
		printf("Failed:\n");
		return 1;
	}

	printf("%s: Success\n", basename(argv[0]));
	return 0;

out_gtod:
	printf("Coding error: gettimeofday returned %d\n", errno);
	return 1;
}
