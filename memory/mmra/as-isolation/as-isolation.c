/*
 * Copyright (C) 2023, Rafael Aquini <aquini@redhat.com>
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
 *   gcc -o as-isolation -D_GNU_SOURCE -lpthread as-isolation.c
 *
 * usage:
 *   ./as-isolation [N]	 -- N: number of forked processes. default/max=26
 *
 *  the program will map 90% of total RAM across a fixed number of forked
 *  processes, and each one of these processes will concurrently write an
 *  unique byte pattern to its private mapped chunk of address space.
 *  After all processes have finish writing to their address space mapped
 *  chunk, they will then concurrently read back the map's contents
 *  asserting that previously written byte pattern.
 */
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <assert.h>
#include <stdio.h>
#include <sched.h>
#include <fcntl.h>
#include <errno.h>
#include <semaphore.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/sysinfo.h>

#ifndef PAGE_SIZE
#define PAGE_SIZE (sysconf(_SC_PAGE_SIZE))
#endif

#define SHARED_SIZE PAGE_SIZE

static const char *prg_name = "as-isolation";
static unsigned long len;
static unsigned long *shared;
static void *addr;
static sem_t *sem;

enum index {COUNTER, WAITING, NCHILD=26};

#define PRINT_ERROR(msg)						   \
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
		PRINT_ERROR(msg);				\
		exit(errno ? errno : EXIT_FAILURE);		\
	} while (0)

#define ERROR_WARN(msg) do { PRINT_ERROR(msg); } while (0)

#ifdef DEBUG
#define DPRINTF(...)						\
	do {							\
		fprintf(stderr, __VA_ARGS__);			\
		fflush(stderr);					\
	} while (0)
#else
#define DPRINTF(...)
#endif

void write_bytes(unsigned long base, unsigned long size, char byte)
{
	unsigned long i;
	for (i = 0; i < size; i++)
		*((char *)base + i) = byte;
}

void read_bytes(unsigned long base, unsigned long size, char byte)
{
	unsigned long i;
	for (i = 0; i < size; i++)
		assert(*((char *)base + i) == byte);
}

int child(int n)
{
	unsigned long base = (unsigned long) addr;
	char byte = (char) n + 'A';

	printf("PID=%ld is writing \"%c\" to the address range %lx-%lx\n",
		(long) getpid(), byte, base, base+len);

	write_bytes(base, len, byte);

	sem_wait(sem);
	shared[COUNTER] += 1;
	sem_post(sem);

	/* wait for all writers to finish */
	while (shared[WAITING])
		sched_yield();

	printf("PID=%ld is reading \"%c\" from the address range %lx-%lx\n",
		(long) getpid(), byte, base, base+len);

	read_bytes(base, len, byte);

	return EXIT_SUCCESS;
}

int main(int argc, char *argv[])
{
	pid_t pid;
	struct sysinfo info;
	int i, ret, status, children;

	children = (argc > 1 ) ? atoi(argv[1]) : NCHILD;
	if (children > NCHILD)
		children = NCHILD;

	if (sysinfo(&info) == -1)
		ERROR_EXIT("sysinfo");

	/* ajusted workingset: 90% of total RAM */
	/* detect overflow in case totalram is too big or children is too small */
	while (1) {
		len = (info.totalram - (info.totalram / 10)) / (unsigned long)children;
		if (len > (info.totalram - (info.totalram / 10))) {
			printf("WARNING: len is bigger than 90%% total RAM. Increase children to %u.\n",
				++children);
		} else {
			break;
		}
	}

	addr = mmap(NULL, len, PROT_READ | PROT_WRITE,
		    MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
	if (addr == MAP_FAILED)
		ERROR_EXIT("mmap");

	/* shared control block */
	shared = mmap(NULL, SHARED_SIZE, PROT_READ | PROT_WRITE,
		      MAP_ANONYMOUS | MAP_SHARED, -1, 0);
	if (shared == MAP_FAILED)
		ERROR_EXIT("mmap");

	shared[COUNTER] = 0;
	shared[WAITING] = 1;

	sem = sem_open(prg_name, O_CREAT, S_IRUSR | S_IWUSR, 0);
	if (sem == SEM_FAILED)
		ERROR_EXIT("sem_open");

	for (i = 0; i < children; i++) {
		pid = fork();
		switch (pid) {
		case -1:	/* fork() has failed */
			ERROR_EXIT("fork");
		case 0:		/* child of a sucessful fork() */
			ret = child(i);
			exit(ret);
		}
	}

	if (-1 == sem_post(sem)) {
		/*	semaphore couldn't release childs execution. 
			Terminate subprocesses and exit */
		kill(0, SIGTERM);
		ERROR_EXIT("sem_post");
	}

	/* wait for all writers to finish */
	while (shared[COUNTER] < (unsigned long) children)
		sched_yield();

	shared[WAITING] = 0;

	for (i = 0;;) {
		if ((pid = wait(&status)) == -1) {
			switch (errno) {
			case ECHILD:
				DPRINTF("PID=%ld (parent) exit!\n", (long) getpid());
				goto out;
			default:
				ERROR_EXIT("wait");
			}
		}

		i++;

		/* assert we're not looping unboundly */
		assert(i <= NCHILD);

		DPRINTF("PID=%ld  wait() returned child PID %ld with status %d (numDead=%d)\n",
			(long) getpid(), (long) pid, WEXITSTATUS(status), i);

		/* assert the child has finished normally */
		assert(WIFEXITED(status) && WEXITSTATUS(status) == EXIT_SUCCESS);
	}
out:
	sem_close(sem);
	sem_unlink(prg_name);

	/*
	 * the parent process has never written to its mapped chunk of address
	 * space, so we should only read zeroes from it.
	 */
	read_bytes((unsigned long) addr, len, 0);

	if (-1 == munmap(addr, len)) {
		ERROR_EXIT("munmap");
	}

	if (-1 == munmap(shared, SHARED_SIZE)) {
		ERROR_EXIT("munmap");
	}

	return EXIT_SUCCESS;
}
