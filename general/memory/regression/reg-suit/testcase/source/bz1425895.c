#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sysexits.h>
#include <time.h>
#include <unistd.h>

#define CHUNKS		1024
#define STACKSIZE	(6ULL * 1024 * 1024)
#define STACKCHUNK	(STACKSIZE / CHUNKS)
//#define HEAPSIZE	(131120ULL * 1024 * 1024)
//#define HEAPCHUNK	(HEAPSIZE / CHUNKS)

static long loop=1;

int main(int argc, char* argv[])
{
	pid_t pid = getpid();
	volatile char rp, s[CHUNKS][STACKCHUNK], *p[CHUNKS];
	unsigned int i, j, k;

	size_t HEAPSIZE = 0, HEAPCHUNK = 0;
	HEAPSIZE  = atol(argv[1]) * 1024 * 1024;
	HEAPCHUNK = HEAPSIZE / CHUNKS;
	if (argc > 2) {
		loop = atol(argv[2]);
	}
	printf("[allocator %u] Run test for %ld times\n", pid, loop);
	printf("[allocator %u] In child, heapsize=%lu\n", pid, HEAPSIZE);

	for (k=0; k < loop; k++) {
		printf("[allocator %u] Allocating memory on stack\n", pid);
		for (i = 0; i < CHUNKS; i++)
			memset((void*)s[i], 0xFF, STACKCHUNK);

		printf("[allocator %u] Allocating memory on heap\n", pid);
		for (i = 0; i < CHUNKS; i++) {
			p[i] = malloc(HEAPCHUNK);
			memset((void*)p[i], 0xFF, HEAPCHUNK);
		}

		printf("[allocator %u] Reading from heap\n", pid);
		for (i = 0; i < CHUNKS; i++)
			for (j = 0; j < HEAPCHUNK; j++)
				rp = p[i][j];

		printf("[allocator %u] Idling\n", pid);
		sleep(60 * 10);

		printf("[allocator %u] Freeing memory\n", pid);
		for (i = 0; i < CHUNKS; i++)
			free((void*)p[i]);
	}
	exit(EXIT_SUCCESS);
}

