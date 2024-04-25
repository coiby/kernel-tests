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
 * compile with: libpthreads required for POSIX semaphores
 *   gcc -o shm-overflow -D_GNU_SOURCE shm-overflow.c
 *
 * usage:
 *   ./shm-overflow
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
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

void child_main(char * shmaddr)
{
	for (int i = 0; i < SHMSIZE; i++) {
		shmaddr[i] = 0xAA;
	}
	printf("Written all shm segment. Attempt to write outside...\n");
	shmaddr[SHMSIZE] = 0xBB;
	exit(EXIT_SUCCESS);
}

int main(void)
{
	int wstatus;

#ifdef USE_POSIX_INTERFACE
#define SHMNAME "/shm-overflow-test"
	int fd = shm_open(SHMNAME, O_RDWR|O_CREAT|O_EXCL, SHMFLAGS);
	if (-1 == fd) {
		perror("shm_open");
		exit(EXIT_FAILURE);
	}
	if (-1 == ftruncate(fd, SHMSIZE)) {
		perror("ftruncate");
		exit(EXIT_FAILURE);
	}
	char * shmaddr = mmap(NULL, SHMSIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
	if ((char *)-1 == shmaddr) {
		perror("mmap");
		exit(EXIT_FAILURE);
	}
#else
#define SHMATFLAGS (0)
#define SHMKEY ((key_t)0xDEADBEEF)
	int shmid = shmget(SHMKEY, SHMSIZE, IPC_CREAT | IPC_EXCL | SHMFLAGS);
	if (-1 == shmid) {
		perror("shmget");
		exit(EXIT_FAILURE);
	}

	char * shmaddr = shmat(shmid, NULL, SHMATFLAGS);
	if ((void *)-1 == shmaddr) {
		perror("shmat");
		exit(EXIT_FAILURE);
	}
#endif

	pid_t pid = fork();
	switch (pid) {
	case 0:
		child_main(shmaddr);
		exit(EXIT_FAILURE); /* in case child_main doesn't call exit() */

	case -1:
		perror("fork");
#ifdef USE_POSIX_INTERFACE
		if (-1 == munmap(shmaddr, SHMSIZE)) {
			perror("munmap");
		}
		if (-1 == close(fd)) {
			perror("close");
		}
		if (-1 == shm_unlink(SHMNAME)) {
			perror("shm_unlink");
		}
#else
		if (-1 == shmctl(shmid, IPC_RMID, NULL)) {
			perror("shmctl");
		}
#endif
		exit(EXIT_FAILURE);

	default:
		pid_t ended_pid = wait(&wstatus);
		if (-1 == ended_pid) {
			perror("wait");
			exit(EXIT_FAILURE);
		}
		break;
	}

#ifdef USE_POSIX_INTERFACE
	if (-1 == munmap(shmaddr, SHMSIZE)) {
		perror("munmap");
		exit(EXIT_FAILURE);
	}
	if (-1 == close(fd)) {
		perror("close");
		exit(EXIT_FAILURE);
	}
	if (-1 == shm_unlink(SHMNAME)) {
		perror("shm_unlink");
		exit(EXIT_FAILURE);
	}
#else
	if (-1 == shmctl(shmid, IPC_RMID, NULL)) {
		perror("shmctl");
		exit(EXIT_FAILURE);
	}
#endif

	printf("Child process terminated with exit status 0x%04X.\n", wstatus);

	if (WIFSIGNALED(wstatus) && (SIGSEGV == WTERMSIG(wstatus))) {
		/* the child process was killed with SIGSEGV: Invalid memory reference */
		printf("Received SIGSEGV as expected.\n");
		exit(EXIT_SUCCESS);
	}

	exit(EXIT_FAILURE);
}
