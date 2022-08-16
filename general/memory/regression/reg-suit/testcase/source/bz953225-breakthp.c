#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/time.h>
#include <time.h>
#include <malloc.h>
#include <mcheck.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
	unsigned long mb;
	int64_t **buf;
	size_t size1, size2;
	int n;
	int i;
	int chunks;

	if (argc < 3) {
		fprintf(stderr, "usage: usemem megabytes chunkkb1 chunkkb2 <sleep>\n");
		exit(1);
	}
	mb = strtoul(argv[1], NULL, 0);
	size1 = strtoul(argv[2], NULL, 0) * 1024L;
	size2 = strtoul(argv[3], NULL, 0) * 1024L;

	chunks = mb * 1024L * 1024L/size1;
	if ((buf = malloc(chunks * sizeof(int64_t *))) == NULL) {
		perror("buf array malloc");
		exit(1);
	}
	n = size1/(sizeof (int64_t));

	fprintf(stderr, "About to test %luMB in %u x %lu kb chunks\n",
			mb, chunks, size1/1024);
	fprintf(stderr, "And then reduce to %luMB in %u x %lu kb chunks\n",
			mb * size1 / size2, chunks, size2/1024);

	for (i = 0; i < chunks; i++) {
		if ((buf[i] = mmap(NULL, size1, PROT_READ|PROT_WRITE,
						MAP_PRIVATE|MAP_ANONYMOUS,
						-1, 0)) == MAP_FAILED) 
			perror ("mmap");
	}

	fprintf (stderr, "Zeroing %ldM\n", mb);
	for (i = 0; i < chunks ; i++)
		memset(buf[i], 0, size1);


	fprintf (stderr, "Writing pattern to %ldM\n", mb);
	for (i = 0; i < chunks; i++) {
		int j;
		for (j = 0; j < n; j++) 
			*(buf[i] + j) = 0xa5a5a5a5a5a5a5a5LL;
	}

	fprintf (stderr, "Remapping to new size %lukb\n", size2/1024);
	for (i = 0; i < chunks; i++)
		buf[i] = mremap (buf[i], size1, size2, MREMAP_MAYMOVE);
	if (buf[i] == MAP_FAILED)
		perror ("mremap");

	/* Optionally sleep for N seconds */
	sleep (atoi (argv[4]));

	fprintf(stderr, "Unmapping memory\n");
	for (i=0; i < chunks; i++) 
		munmap(buf[i], size2);

	exit(0);
}

