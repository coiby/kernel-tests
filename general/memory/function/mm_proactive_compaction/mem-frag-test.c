/*
 * mem-frag-test.c: forces system memory fragmentation by mapping a THP-backed
 *		    area with the size of total available RAM in the system,
 *		    only to release half of that allocated memory by punching
 *		    small holes across the mapping breaking the 2MB-aligned
 *		    chunks into thousands of smaller some-power-of-2 KB maps.
 *
 * Copyright (C) 2020, Rafael Aquini <aquini@redhat.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *
 *  2. Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation
 *     and/or other materials provided with the distribution.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 *  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 *  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 *  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS
 *  BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 *  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 *  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 *  BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 *  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 *  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 *  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#define _GNU_SOURCE /* needed for asprintf */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>

static const char *prg_name;

#define __PRINT_ERROR(msg)						   \
	do {								   \
		char *estr;						   \
		asprintf(&estr, "[%s:%d] %s: %s (%d)",			   \
			 __FILE__, __LINE__, msg, strerror(errno), errno); \
		fprintf(stderr, "%s\n", estr);				   \
		fflush(stderr);						   \
		free(estr);						   \
	} while (0)

#define ERROR_EXIT(msg)						\
	do {							\
		__PRINT_ERROR(msg);				\
		exit(errno ? errno : EXIT_FAILURE);		\
	} while (0)

#define ERROR_WARN(msg) do { __PRINT_ERROR(msg); } while (0)

#ifdef DEBUG
#define DPRINTF(...)						\
	do {							\
		fprintf(stderr, __VA_ARGS__);			\
		fflush(stderr);					\
	}
#else
#define DPRINTF(...)
#endif

#define MUNMAP_CHECK(a, l)					\
	do {							\
		if (munmap((a), (l)))				\
			ERROR_WARN("munmap");			\
	} while (0)

#define MADVISE_CHECK(a, l, m)					\
	do {							\
		if (madvise((a), (l), (m)))			\
			ERROR_WARN("madvise");			\
	} while (0)

#ifndef DIVIDER
/* this must be in powers of 2 */
#define DIVIDER 256
#endif

#define THP_SIZE	(1ULL << 21)

void write_random_bytes(void *addr, unsigned long len)
{
	unsigned long i;
	pid_t pid = getpid();

	DPRINTF("%s-%d: %ldmB of memory mapped in the range %lx-%lx \n",
		prg_name, pid, len >> 20, (unsigned long)addr, (unsigned long)addr + len);

	srand(time(NULL) + pid);
	for (i = 0; i < len; i++) {
		char byte = 'A' + (rand() % 26);
		*((char *)addr + i) = byte;
	}
}

/*
 * unmap_chunks: forces fragmentation by splitting a 2MB-aligned contiguous
 * huge anonymous mapping (THP) into several chunks of THP_SIZE/DIVIDER size
 * and releasing half of them interleaved.
 */
void unmap_chunks(void *addr, unsigned long len)
{
	unsigned long i;
	unsigned long base = (unsigned long)addr;
	unsigned long chunk = THP_SIZE / DIVIDER;
	unsigned long stride = 2 * chunk;

	DPRINTF("%s-%d: unmapping chunks of %ldkB every %ldkB in the range %lx-%lx\n",
		prg_name, getpid(), (chunk >> 10), (stride >> 10), base, base + len);

	for (i = base; i < base + len - stride; i += stride) {
		MADVISE_CHECK((void *)i, chunk, MADV_FREE);
		MUNMAP_CHECK((void *)i, chunk);
	}
}

bool check_max_map_count(unsigned long map_count)
{
	FILE *stream;
	char *line = NULL;
	size_t len = 0;
	ssize_t nread;
	unsigned long max_map_count = 0;

	stream = fopen("/proc/sys/vm/max_map_count", "r");
	if (!stream)
		ERROR_EXIT("fopen");

	nread = getline(&line, &len, stream);
	if (nread == -1)
		ERROR_EXIT("getline");

	sscanf(line, "%li", &max_map_count);

	fclose(stream);
	free(line);

	return (max_map_count >= map_count);
}

void set_max_map_count(unsigned long map_count)
{
	FILE *stream;
	char *line = NULL;
	ssize_t nbytes;

	nbytes = asprintf(&line, "%li\n", map_count);
	stream = fopen("/proc/sys/vm/max_map_count", "w");
	if (!stream)
		ERROR_EXIT("fopen");

	if (!fwrite(line, sizeof(char), nbytes, stream))
		ERROR_EXIT("fwrite");

	DPRINTF("%s-%d: adjusted /proc/sys/vm/max_map_count to %ld\n",
		prg_name, getpid(), map_count);

	fclose(stream);
	free(line);
}

/*
 * clp2: Computes the least power of 2 greater than or equal to x (32-bit)
 * as implemented by Henry S. Warren, Jr. in his book Hacker's Delight.
 */
unsigned long clp2(unsigned long x)
{
	x = x - 1;
	x = x | (x >> 1);
	x = x | (x >> 2);
	x = x | (x >> 4);
	x = x | (x >> 8);
	x = x | (x >> 16);

	return x + 1;
}

int main(int argc, char *argv[])
{
	void *addr;
	unsigned long len;
	struct sysinfo info;
	unsigned long map_count;
	int sleep_and_exit = (argc > 1) ? atoi(argv[1]) : 0;

	if (sysinfo(&info) == -1)
		ERROR_EXIT("sysinfo");

	prg_name = argv[0];
	len = info.totalram * 9 / 10;
	addr = mmap(NULL, len, PROT_READ | PROT_WRITE,
		    MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
	if (addr == MAP_FAILED)
		ERROR_EXIT("mmap");

	/* hint the kernel to back the map with THPs */
	MADVISE_CHECK(addr, len, MADV_HUGEPAGE);

	write_random_bytes(addr, len);

	/*
	 * Depending on the amount of available RAM and the value defined as
	 * DIVIDER, this program will require more VMAs than what the kernel
	 * allows a process to create (by default 65530).
	 * The sysctl vm.max_map_count needs to be adjusted accordingly
	 * in order to allow for the unmaps.
	 */
	map_count = clp2(len / (2 * THP_SIZE / DIVIDER));
	if (!check_max_map_count(map_count))
		set_max_map_count(map_count);

	unmap_chunks(addr, len);

	fprintf(stdout, "%s-%d: buddy system fragmented! going for a %s snap...\n",
		prg_name, getpid(), sleep_and_exit ? "short" : "long");
	fflush(stdout);

	/*
	 * sleep_and_exit can be utilized to select a small delay before
	 * exiting, instead of infinite looping with the fragmented mem,
	 * if the test case wants to cycle through rounds of getting the
	 * system memory fragmented and de-fragmented N times in a row.
	 */
	if (!sleep_and_exit) {
		for (;;)
			sleep(1);
	} else {
		sleep(sleep_and_exit);
	}

	return EXIT_SUCCESS;
}
