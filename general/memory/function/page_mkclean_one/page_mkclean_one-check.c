/*
 * Check to make sure page_mkclean_one behaves correctly. Data corruption
 * is a Bad Thing, mmmkay?
 *     http://bugzilla.redhat.com/220963
 *
 * Original version written by Linus Torvalds, can be found here:
 * http://marc.info/?l=linux-kernel&m=116726650423768&w=2
 */

#include <sys/mman.h>
#include <sys/fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

#define TARGETSIZE (500 << 20)
#define CHUNKSIZE (1460)
#define NRCHUNKS (TARGETSIZE / CHUNKSIZE)
#define SIZE (NRCHUNKS * CHUNKSIZE)

static void fillmem(void *start, int nr)
{
	memset(start, nr, CHUNKSIZE);
}

static void checkmem(void *start, int nr)
{
	unsigned char c = nr, *p = start;
	int i;
	for (i = 0; i < CHUNKSIZE; i++) {
		if (*p++ != c) {
			printf("Chunk %d corrupted           \n", nr);
			return;
		}
	}
}

static char *remap(int fd, char *mapping)
{
	if (mapping) {
		munmap(mapping, SIZE);
		posix_fadvise(fd, 0, SIZE, POSIX_FADV_DONTNEED);
	}
	return mmap(NULL, SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
}

int main(int argc, char **argv)
{
	char *mapping;
	int fd, i;
	static int chunkorder[NRCHUNKS];

	/*
	 * Make some random ordering of writing the chunks to the
	 * memory map..
	 *
	 * Start with fully ordered..
	 */
	for (i = 0; i < NRCHUNKS; i++)
		chunkorder[i] = i;

	/* ..and then mix it up randomly */
	srandom(time(NULL));
	for (i = 0; i < NRCHUNKS; i++) {
		int index = (unsigned int) random() % NRCHUNKS;
		int nr = chunkorder[index];
		chunkorder[index] = chunkorder[i];
		chunkorder[i] = nr;
	}

	fd = open("mapfile", O_RDWR | O_TRUNC | O_CREAT, 0666);
	if (fd < 0)
		return -1;
	if (ftruncate(fd, SIZE) < 0)
		return -1;
	mapping = remap(fd, NULL);
	if (-1 == (int)(long)mapping)
		return -1;

	for (i = 0; i < NRCHUNKS; i++) {
		int chunk = chunkorder[i];
		printf("Writing chunk %d/%d (%d%%)     \r",
		       i, NRCHUNKS, 100*i/NRCHUNKS);
		fillmem(mapping + chunk * CHUNKSIZE, chunk);
	}
	printf("\n");

	/* Unmap, drop, and remap.. */
	mapping = remap(fd, mapping);

	/* .. and check */
	for (i = 0; i < NRCHUNKS; i++) {
		int chunk = i;
		printf("Checking chunk %d/%d (%d%%)     \r",
		       i, NRCHUNKS, 100*i/NRCHUNKS);
		checkmem(mapping + chunk * CHUNKSIZE, chunk);
	}
	printf("\n");

	return 0;
}

