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
 *   ./shm-create [create|read|delete] # creates / reads (assert) from / deletes the shm segment
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
#include <sys/mman.h>
#include <sys/stat.h>        /* For mode constants */
#include <fcntl.h>           /* For O_* constants */

#ifndef PAGE_SIZE
#define PAGE_SIZE (sysconf(_SC_PAGE_SIZE))
#endif

#define SHMSIZE ((size_t)PAGE_SIZE)
#define SHMFLAGS (0600)

typedef enum {CREATE, READ, DELETE} options_t;

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
	} else if (!strcmp(argv[1], "delete")) {
		option = DELETE;
	} else {
		fprintf(stderr, "wrong option\n");
		exit(EXIT_FAILURE);
	}

#ifdef USE_POSIX_INTERFACE
#define SHMNAME "/shm-access-test"
	switch (option) {
	case CREATE:
		int fd = shm_open(SHMNAME, O_RDWR|O_CREAT|O_EXCL, SHMFLAGS);
		if (-1 == fd) {
			perror("shm_open");
			exit(EXIT_FAILURE);
		}
		if (-1 == ftruncate(fd, SHMSIZE)) {
			perror("ftruncate");
			exit(EXIT_FAILURE);
		}
		unsigned char * shmaddr = mmap(NULL, SHMSIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
		if ((unsigned char *)-1 == shmaddr) {
			perror("mmap");
			exit(EXIT_FAILURE);
		}
		for (int i = 0; i < SHMSIZE; i++) {
			shmaddr[i] = 0xAA;
		}
		if (-1 == munmap(shmaddr, SHMSIZE)) {
			perror("munmap");
			exit(EXIT_FAILURE);
		}
		if (-1 == close(fd)) {
			perror("close");
			exit(EXIT_FAILURE);
		}
		break;

	case READ:
		fd = shm_open(SHMNAME, O_RDONLY, SHMFLAGS);
		if (-1 == fd) {
			perror("shm_open");
			exit(EXIT_FAILURE);
		}
		shmaddr = mmap(NULL, SHMSIZE, PROT_READ, MAP_SHARED, fd, 0);
		if ((unsigned char *)-1 == shmaddr) {
			perror("mmap");
			exit(EXIT_FAILURE);
		}
		for (int i = 0; i < SHMSIZE; i++) {
			assert(shmaddr[i] == 0xAA);
		}
		if (-1 == munmap(shmaddr, SHMSIZE)) {
			perror("munmap");
			exit(EXIT_FAILURE);
		}
		if (-1 == close(fd)) {
			perror("close");
			exit(EXIT_FAILURE);
		}
		break;

	case DELETE:
		if (-1 == shm_unlink(SHMNAME)) {
			perror("shm_unlink");
			exit(EXIT_FAILURE);
		}

	default:
		break;
	}
#else
#define SHMKEY ((key_t)0xDEADBEEF)
#define SHMATFLAGS (0)
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

	case DELETE:
		fprintf(stderr, "Not supported. Use ipcrm for SysV shared memory.");
		exit(EXIT_FAILURE);

	default:
		break;
	}
#endif

	exit(EXIT_SUCCESS);
}
