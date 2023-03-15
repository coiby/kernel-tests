/*
 * Copyright 2017, Red Hat, Inc.
 * Author: Jeff Moyer <jmoyer@redhat.com>
 * License: GPLv2+
 *
 * Test badblocks code by artificially injecting a badblock, and then
 * triggerring a load from that block.  Ensure that we get SIGBUS and
 * that the address field is valid.  Then, try to recover by write(2)-ing
 * new data to the data block, and then retry the load.
 *
 * It would be nice if we could also test with the EINJ framework, but
 * recovering from that on some platforms is very painful (bios
 * intervention is required).
 *
 * This code expects the file system to be mounted with -o dax.
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <limits.h>
#include <signal.h>
#include <setjmp.h>
#include <sys/mman.h>

static int pagesize;
static jmp_buf env;
static void *fault_addr;

void
usage(const char *prog)
{
	fprintf(stderr, "Usage: %s <filename> <offset>\n", prog);
	fprintf(stderr, "\toffset: file offset containing a media error.\n");
}

void
sigbus_action(int __attribute__((unused)) signo,
	      siginfo_t *siginfo, void __attribute__((unused)) *ucontext)
{
	fault_addr = siginfo->si_addr;
	longjmp(env, 1);
}

int
main(int argc, char **argv)
{
	int fd;
	int ret;
	void *map;
	off_t offset;
	char c;
	struct sigaction act;
	static int signaled;
	char *buf;

	if (argc != 3) {
		usage(basename(argv[0]));
		exit(1);
	}

	pagesize = getpagesize();
	buf = calloc(pagesize, 1);

	offset = strtoll(argv[2], NULL, 10);
	if (offset == LLONG_MIN || offset == LLONG_MAX) {
		if (errno == ERANGE) {
			fprintf(stderr, "invalid offset\n");
			exit(1);
		}
	}

	fd = open(argv[1], O_RDWR);
	if (fd < 0) {
		perror("open");
		exit(1);
	}

	map = mmap(NULL, pagesize, PROT_READ | PROT_WRITE,
		   MAP_SHARED, fd, offset);
	if (map == MAP_FAILED) {
		perror("mmap");
		exit(1);
	}

	/*
	 * Setup a signal hander for SIGBUS.
	 */
	act.sa_sigaction = sigbus_action;
	sigemptyset(&act.sa_mask);
	act.sa_flags = SA_SIGINFO;

	ret = sigaction(SIGBUS, &act, NULL);
	if (ret < 0) {
		perror("sigaction");
		exit(1);
	}

	if (!setjmp(env))
		c = *(char *)map;
	else {
		printf("Got (expected) SIGBUS dereferencing address %p, "
		       "file block %lu\n", map, offset);
		if (fault_addr != map) {
			printf("got a fault on address %p, expected %p\n",
			       fault_addr, map);
			printf("Test Failed\n");
		}
		signaled = 1;
	}

	/* If we didn't hit sigbus, there's no error to clear. */
	if (!signaled)
		goto fail;

#ifdef CLEAR_ERROR_WORKS
	/* now clear the error with a write(2) */
	ret = write(fd, buf, pagesize);
	if (ret != pagesize) {
		fprintf(stderr, "unable to clear error.  write returned %d\n",
			ret);
		if (ret < 0)
			perror("write");

	}

	/*
	 * Now retry the load.  We restore the default handler for
	 * SIGBUS, meaning the program will terminate if the clear
	 * error failed.
	 */
	act.sa_handler = SIG_DFL;
	sigemptyset(&act.sa_mask);
	act.sa_flags = 0;
	ret = sigaction(SIGBUS, &act, NULL);
	if (ret < 0) {
		perror("sigaction");
		exit(1);
	}

	/* If clear error is supported, this should now succeed */
	c = *(char *)map;

#endif /* CLEAR_ERROR_WORKS */

	printf("Test Completed Successfully\n");
	return 0;

fail:
	printf("Test Failed\n");
	exit(1);
}
/*
 * Local variables:
 *  compile-command: "gcc -O0 -g3 -W -o sigbus sigbus.c"
 * End:
 */
