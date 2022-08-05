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

int main(int argc, char * argv[])
{
	int j;
	FILE *f;
	struct timeval now, tv_start, tv_end;
	f = fopen ("myfile.txt","a");

	if (argc > 1) {
		return 1;
	}

	gettimeofday(&now,NULL);
	fprintf(f, "%10ld.%06ds\n", (long int)now.tv_sec,
               (int)now.tv_usec);

	fclose (f);
	return 0;
}
