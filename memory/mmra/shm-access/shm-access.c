/*
 * Copyright (C) 2024, Pablo Ridolfi <pridolfi@redhat.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 * compile with:
 *   gcc -o shm-access -D_GNU_SOURCE shm-access.c
 *
 * usage:
 *   ./shm-access
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <string.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/shm.h>

#ifndef PAGE_SIZE
#define PAGE_SIZE (sysconf(_SC_PAGE_SIZE))
#endif

#define SHMKEY ((key_t)0xDEADBEEF)
#define SHMSIZE ((size_t)PAGE_SIZE)
#define SHMFLAGS (0)
#define SHMATFLAGS (0)


int main(int argc, char *argv[])
{
	printf("Attempt to open and attach shm segment... ");
	int shmid = shmget(SHMKEY, SHMSIZE, SHMFLAGS);
	if (-1 == shmid) {
		perror("shmget");
		exit(EXIT_FAILURE);
	}

	unsigned char * shmaddr = shmat(shmid, NULL, SHMATFLAGS);
	if ((void *)-1 == shmaddr) {
		perror("shmat");
		exit(EXIT_FAILURE);
	}
	printf("OK\n");

	printf("Attempt to read shm segment... ");
	for (int i = 0; i < SHMSIZE; i++) {
		assert(shmaddr[i] == 0xAA);
	}
	printf("OK\n");

	printf("Attempt to write shm segment... ");
	for (int i = 0; i < SHMSIZE; i++) {
		shmaddr[i] = 0xBB;
	}
	printf("OK\n");

	exit(EXIT_SUCCESS);
}
