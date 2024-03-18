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
 *   gcc -o shm-create -D_GNU_SOURCE shm-create.c
 *
 * usage:
 *   ./shm-create create|read] # creates / reads (assert) from the shm segment
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
#define SHMFLAGS (0600)
#define SHMATFLAGS (0)

typedef enum {CREATE, READ} options_t;

int main(int argc, char *argv[])
{
	if (argc < 2) {
		fprintf(stderr, "wrong arguments\n");
		exit(EXIT_FAILURE);
	}

	options_t option;
	if (!strcmp(argv[1], "create")) {
		option = CREATE;
	} else if (!strcmp(argv[1], "read")) {
		option = READ;
	} else {
		fprintf(stderr, "wrong option\n");
		exit(EXIT_FAILURE);
	}

	switch (option) {
	case CREATE:
		int shmid = shmget(SHMKEY, SHMSIZE, IPC_CREAT | IPC_EXCL | SHMFLAGS);
		if (-1 == shmid) {
			perror("shmget");
			exit(EXIT_FAILURE);
		}
		
		unsigned char * shmaddr = shmat(shmid, NULL, SHMATFLAGS);
		if ((void *)-1 == shmaddr) {
			perror("shmat");
			exit(EXIT_FAILURE);
		}

		for (int i = 0; i < SHMSIZE; i++) {
			shmaddr[i] = 0xAA;
		}
		break;

	case READ:
		shmid = shmget(SHMKEY, SHMSIZE, 0);
		if (-1 == shmid) {
			perror("shmget");
			exit(EXIT_FAILURE);
		}

		shmaddr = shmat(shmid, NULL, SHMATFLAGS);
		if ((void *)-1 == shmaddr) {
			perror("shmat");
			exit(EXIT_FAILURE);
		}

		for (int i = 0; i < SHMSIZE; i++) {
			assert(shmaddr[i] == 0xAA);
		}
		break;

	default:
		break;
	}

	exit(EXIT_SUCCESS);
}
