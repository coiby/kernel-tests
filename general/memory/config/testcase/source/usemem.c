#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/time.h>
#include <time.h>
#include <malloc.h>
#include <mcheck.h>

#define CHUNKS 32


static void timing_start (struct timeval *initv)
{
	gettimeofday (initv, NULL);
	return;
}

static void timing_print (struct timeval *initv)
{
	struct timeval tv;
	struct timeval result;

	gettimeofday (&tv, NULL);
	timersub (&tv, initv, &result);

	fprintf (stderr, "Took %ld.%03ld seconds\n", result.tv_sec,
			result.tv_usec/1000);
	return;
}

int main(int argc, char *argv[])
{
	unsigned long mb;
	int64_t *buf[CHUNKS];
	size_t size;
	int n;
	int i;
	struct timeval tvp[1];

	if (argc < 2) {
		fprintf(stderr, "usage: usemem megabytes\n");
		exit(1);
	}
	mb = strtoul(argv[1], NULL, 0);

	size = (mb * 1024L * 1024L)/CHUNKS;
	n = size/(sizeof (int64_t));

	for (i = 0; i < CHUNKS; i++) {
		if (!(buf[i] = malloc (size)))
			perror ("malloc");
	}

	timing_start (tvp);
	fprintf (stderr, "Zeroing %ldM\n", mb);
	for (i = 0; i < CHUNKS; i++)
		memset(buf[i], 0, size);

	timing_print (tvp);

	fprintf (stderr, "Writing pattern to %ldM\n", mb);
	timing_start (tvp);
	for (i = 0; i < CHUNKS; i++) {
		int j;
		for (j = 0; j < n; j++) 
			*(buf[i] + j) = 0xa5a5a5a5a5a5a5a5LL;
	}
	timing_print (tvp);

	fprintf (stderr, "Reading back %ldM\n", mb);
	timing_start (tvp);
	{
		int niters = 10;
		while (niters--) {
			for (i = 0; i < CHUNKS; i++) {
				int j;
				for (j = 0; j < n; j++)  {
					int64_t *vp = buf[i] + j;
					int64_t v = *vp;
				}
			}
		}
	}
	timing_print (tvp);

	/* Optionally sleep for N seconds */
	sleep (atoi (argv[2]));

	fprintf (stderr, "Freeing %ldM\n", mb);
	timing_start (tvp);
	for (i = 0; i < CHUNKS; i++)
		free (buf[i]);
	timing_print (tvp);

	exit(0);
}
